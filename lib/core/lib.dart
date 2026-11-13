import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'desktop/model.dart';
import 'interface.dart';
import 'method.dart';
import 'spill.dart';

class CoreLib extends CoreHandlerInterface {
  static CoreLib? _instance;

  final Service? _service;
  final bool _listenerManagedByService;

  // iOS only: which side started the running listeners. The service owns
  // them while the tunnel runs; the App core owns them in core-only mode.
  var _listenersStartedByService = true;

  Completer<bool> _connectedCompleter = Completer<bool>();
  Future<CoreLifecycleResult>? _closeOperation;
  int _lifecycleRevision = 0;
  int _methodCallId = 0;
  bool _closed = false;

  CoreLib._internal()
    : _service = service,
      _listenerManagedByService = system.isIOS;

  @visibleForTesting
  CoreLib.scoped(Service this._service, {bool listenerManagedByService = false})
    : _listenerManagedByService = listenerManagedByService;

  @visibleForTesting
  static void resetInstance() {
    _instance = null;
  }

  factory CoreLib() {
    _instance ??= CoreLib._internal();
    return _instance!;
  }

  @override
  Future<CoreLifecycleResult> start() async {
    if (_closed) {
      throw StateError('Core lifecycle is closed');
    }
    final revision = ++_lifecycleRevision;
    if (_connectedCompleter.isCompleted) {
      return CoreLifecycleResult(
        revision: revision,
        outcome: CoreLifecycleOutcome.coalesced,
      );
    }
    final initializationError = await _service?.init() ?? '';
    if (initializationError.isNotEmpty) {
      throw StateError(initializationError);
    }
    await globalState.container.read(vpnOptionsProvider.future);
    _connectedCompleter.complete(true);
    final syncError =
        await _service?.syncState(
          globalState.container.read(sharedStateProvider),
        ) ??
        '';
    if (syncError.isNotEmpty) {
      _connectedCompleter = Completer<bool>();
      await _service?.shutdown();
      throw StateError(syncError);
    }
    return CoreLifecycleResult(
      revision: revision,
      outcome: CoreLifecycleOutcome.applied,
    );
  }

  @override
  Future<CoreLifecycleResult> restart() async {
    await stop();
    return start();
  }

  @override
  Future<CoreLifecycleResult> stop() => _stop();

  Future<CoreLifecycleResult> _stop({bool allowClosed = false}) async {
    if (_closed && !allowClosed) {
      throw StateError('Core lifecycle is closed');
    }
    final revision = ++_lifecycleRevision;
    if (!_connectedCompleter.isCompleted) {
      return CoreLifecycleResult(
        revision: revision,
        outcome: CoreLifecycleOutcome.coalesced,
      );
    }
    _connectedCompleter = Completer<bool>();
    final stopped = await _service?.shutdown() ?? true;
    if (!stopped) {
      throw StateError('Mobile Core service shutdown failed');
    }
    return CoreLifecycleResult(
      revision: revision,
      outcome: CoreLifecycleOutcome.applied,
    );
  }

  @override
  Future<CoreLifecycleResult> close() {
    return _closeOperation ??= _close();
  }

  Future<CoreLifecycleResult> _close() async {
    _closed = true;
    return _stop(allowClosed: true);
  }

  @override
  Future<void> startListener() async {
    if (_listenerManagedByService) {
      await _startIOSListener();
      return;
    }
    await _ignoreUnanswered(super.startListener);
    if (!await _service!.start()) {
      throw const CoreMethodException(
        code: 'service_refused',
        message: 'The Android service did not start',
      );
    }
  }

  Future<void> _startIOSListener() async {
    if (!await _isVpnEnabled()) {
      await invokeMethod(
        method: CoreMethod.listenerStart,
        route: CoreRoute.app,
      );
      _listenersStartedByService = false;
      return;
    }
    // The service opens and closes the Core's listeners itself and reports a
    // run that ends, so once it takes the command the Core's own answer is moot.
    if (!await _service!.start()) {
      throw const CoreMethodException(
        code: 'service_refused',
        message: 'The iOS service did not start',
      );
    }
    _listenersStartedByService = true;
  }

  Future<bool> _isVpnEnabled() async {
    final vpnOptions = await globalState.container.read(
      vpnOptionsProvider.future,
    );
    return vpnOptions.enable;
  }

  @override
  Future<void> stopListener() async {
    if (_listenerManagedByService && !_listenersStartedByService) {
      // Core-only mode: stop the App core's own listeners (best-effort).
      await _ignoreUnanswered(
        () =>
            invokeMethod(method: CoreMethod.listenerStop, route: CoreRoute.app),
      );
      return;
    }
    final serviceStopped = await _service!.stop();
    if (!_listenerManagedByService) {
      await _ignoreUnanswered(super.stopListener);
    }
    if (!serviceStopped) {
      throw const CoreMethodException(
        code: 'service_refused',
        message: 'The mobile service did not stop',
      );
    }
  }

  Future<void> _ignoreUnanswered(Future<void> Function() command) async {
    try {
      await command();
    } catch (error) {
      if (!isUnansweredCoreError(error)) {
        rethrow;
      }
    }
  }

  @override
  Future<Object?> invokeMethod({
    required CoreMethod method,
    Object? arguments,
    Duration? timeout,
    CoreRoute? route,
  }) {
    final call = _send(method: method, arguments: arguments, route: route);
    return call.withTimeout(
      timeout: timeout,
      onTimeout: () {
        unawaited(call.then(discardSpilledFile, onError: (_) {}));
        throw TimeoutException('Core method ${method.wireName} timed out');
      },
    );
  }

  Future<Object?> _send({
    required CoreMethod method,
    Object? arguments,
    CoreRoute? route,
  }) async {
    try {
      await _connectedCompleter.future.timeout(coreConnectionWaitDuration);
    } on TimeoutException {
      throw CoreMethodException(
        code: 'core_unavailable',
        message: 'Core is not connected for ${method.wireName}',
      );
    }
    final id = '${++_methodCallId}';
    try {
      final response = await _service!.invokeMethod(
        CoreMethodCall(
          id: id,
          method: method,
          arguments: arguments,
          route: route,
        ),
      );
      return response.unwrap<Object?>();
    } on CoreMethodException catch (error) {
      if (error.code == 'empty_response') {
        // Name the unanswered call so the log shows which piece failed.
        commonPrint.log(
          'xpc empty_response: ${method.wireName}',
          logLevel: LogLevel.warning,
        );
      }
      rethrow;
    }
  }
}

// iOS uses CoreLib too (fork parity): isAndroid alone leaves coreLib null
// on iOS and crashes startup in CoreController (null check at
// controller.dart:22).
CoreLib? get coreLib => system.isMobile ? CoreLib() : null;
