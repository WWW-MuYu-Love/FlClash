import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/event.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/core/spill.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final _utf8JsonDecoder = utf8.decoder.fuse(json.decoder);

Object? _decodeUtf8Json(Uint8List data) => _utf8JsonDecoder.convert(data);

Map<String, Object?> _decodeResponseOf((Uint8List, CoreResultModel?) request) {
  final (data, model) = request;
  final decoded = _decodeUtf8Json(data);
  return withResultModel(model, Map<String, Object?>.from(decoded as Map));
}

Future<Map<String, Object?>> _decodeResponse(
  Uint8List data,
  CoreResultModel? model,
) async {
  if (data.length < coreIsolateDecodeBytes) {
    return _decodeResponseOf((data, model));
  }
  return compute(_decodeResponseOf, (data, model));
}

abstract mixin class ServiceListener {
  void onServiceEvent(CoreEvent event) {}

  void onServiceStopped([ServiceStartFailure? failure]) {}
}

enum TunnelState { pending, connected, disconnected }

/// Reads a tunnel start failure report from the service channel. The
/// Runner sends a map with the diagnosis code and the detail; a bare
/// string from an older sender is kept as an undiagnosed failure.
TunnelStartFailure _tunnelStartFailure(Object? arguments) {
  if (arguments is Map) {
    final code = arguments['code'];
    final detail = arguments['detail'];
    if (code is String && detail is String) {
      return (code: code, detail: detail);
    }
  }
  if (arguments is String) {
    return (code: 'unknown', detail: arguments);
  }
  return (code: 'unknown', detail: '');
}

class Service {
  static Service? _instance;
  late MethodChannel methodChannel;
  static const _coreChannel = MethodChannel('$packageName/core');

  final _tunnelState = ValueNotifier(TunnelState.pending);

  ValueListenable<TunnelState> get tunnelState => _tunnelState;

  final _tunnelError = ValueNotifier<TunnelStartFailure?>(null);

  ValueListenable<TunnelStartFailure?> get tunnelError => _tunnelError;

  final ObserverList<ServiceListener> _listeners =
      ObserverList<ServiceListener>();

  int _commandRevision = 0;
  bool _startRequested = false;

  factory Service() {
    _instance ??= Service._internal();
    return _instance!;
  }

  Service._internal() {
    methodChannel = const MethodChannel('$packageName/service');
    methodChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'tunnelState':
          _tunnelState.value = TunnelState.values.byName(
            call.arguments as String,
          );
          break;
        case 'tunnelError':
          final failure = _tunnelStartFailure(call.arguments);
          _tunnelError.value = failure;
          commonPrint.log(
            'Tunnel failed: ${failure.code} ${failure.detail}',
            logLevel: LogLevel.error,
          );
          break;
        case 'event':
          final methodCall = CoreMethodCall.fromJson(
            Map<String, Object?>.from(
              _decodeUtf8Json(call.arguments as Uint8List) as Map,
            ),
          );
          for (final event in coreEventsFromData(methodCall.arguments)) {
            _dispatch(
              'Core event ${event.type.name}',
              (listener) => listener.onServiceEvent(event),
            );
          }
          break;
        case 'stopped':
          final report = call.arguments as Map<Object?, Object?>;
          // A report stamped before the newest command no longer describes it.
          if (report['revision'] != _commandRevision || !_startRequested) {
            break;
          }
          _startRequested = false;
          final failure = ServiceStartFailure.fromCode(report['failure']);
          _dispatch(
            'stop report',
            (listener) => listener.onServiceStopped(failure),
          );
          break;
        default:
          throw MissingPluginException();
      }
    });
  }

  Future<CoreMethodResponse> invokeMethod(
    CoreMethodCall call, {
    CoreResultModel? model,
  }) async {
    model ??= coreResultModelOf(call.method);
    final data = await _coreChannel.invokeMethod<Uint8List>(
      'invokeMethod',
      json.encode(call),
    );
    if (data == null) {
      throw CoreMethodException(
        code: 'no_response',
        message: 'Core did not answer ${call.method.wireName}',
      );
    }
    return resolveSpilledResponse(
      CoreMethodResponse.fromJson(await _decodeResponse(data, model)),
      model: model,
    );
  }

  void _dispatch(String label, void Function(ServiceListener) deliver) {
    for (final listener in List.of(_listeners)) {
      try {
        deliver(listener);
      } catch (error) {
        commonPrint.log(
          'Unable to dispatch Android $label: $error',
          logLevel: LogLevel.error,
        );
      }
    }
  }

  Future<bool> start() async {
    _startRequested = true;
    _tunnelError.value = null;
    return await methodChannel
            .invokeMethod<bool>('start', ++_commandRevision)
            .timeout(const Duration(seconds: 30)) ??
        false;
  }

  Future<bool> stop() async {
    _startRequested = false;
    return await methodChannel
            .invokeMethod<bool>('stop', ++_commandRevision)
            .timeout(const Duration(seconds: 30)) ??
        false;
  }

  Future<String> init() async {
    return await methodChannel
            .invokeMethod<String>('init')
            .timeout(const Duration(seconds: 30)) ??
        '';
  }

  Future<String> syncState(SharedState state) async {
    return await methodChannel
            .invokeMethod<String>('syncState', json.encode(state))
            .timeout(const Duration(seconds: 30)) ??
        '';
  }

  Future<bool> shutdown() async {
    return await methodChannel
            .invokeMethod<bool>('shutdown')
            .timeout(const Duration(seconds: 10)) ??
        true;
  }

  /// Asks the runner to re-read the tunnel state once. The fresh state
  /// arrives through the tunnelState channel; a failure only skips this
  /// re-read.
  Future<void> refreshTunnelState() async {
    await methodChannel
        .invokeMethod<void>('refreshTunnelState')
        .timeout(const Duration(seconds: 10));
  }

  Future<DateTime?> getRunTime() async {
    int? ms;
    try {
      ms = await methodChannel
          .invokeMethod<int>('getRunTime')
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return null;
    }
    if (ms == null || ms == 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<({bool active, Mode? restoreMode})> getSsidDirectOverride() async {
    Map<Object?, Object?>? result;
    try {
      result = await methodChannel
          .invokeMethod<Map<Object?, Object?>>('getSsidDirectOverride')
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return (active: false, restoreMode: null);
    }
    if (result == null) {
      return (active: false, restoreMode: null);
    }
    final restoreMode = result['restoreMode'];
    return (
      active: result['active'] == true,
      restoreMode: restoreMode is String
          ? Mode.values.where((mode) => mode.name == restoreMode).firstOrNull
          : null,
    );
  }

  bool get hasListeners {
    return _listeners.isNotEmpty;
  }

  void addListener(ServiceListener listener) {
    _listeners.add(listener);
  }

  void removeListener(ServiceListener listener) {
    _listeners.remove(listener);
  }
}

Service? get service => system.isAndroid || system.isIOS ? Service() : null;
