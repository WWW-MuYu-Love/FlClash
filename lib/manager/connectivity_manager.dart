import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/wifi_ssid.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/on_demand.dart';
import 'package:flutter/widgets.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_api/rust_api.dart' show NetworkState, networkChanges;

typedef SsidReader = Future<String?> Function();

class ConnectivityManager extends ConsumerStatefulWidget {
  final Function(NetworkState state)? onConnectivityChanged;
  final Stream<NetworkState>? connectivityStream;
  final SsidReader? readSsid;
  final Widget child;

  const ConnectivityManager({
    super.key,
    this.onConnectivityChanged,
    this.connectivityStream,
    this.readSsid,
    required this.child,
  });

  @override
  ConsumerState<ConnectivityManager> createState() =>
      _ConnectivityManagerState();
}

class _ConnectivityManagerState extends ConsumerState<ConnectivityManager>
    with WidgetsBindingObserver {
  late final StreamSubscription subscription;
  late final SsidReader _readSsid = widget.readSsid ?? wifiSsidManager.getSsid;

  int _ssidRequestId = 0;
  bool _onWifi = false;
  bool _streamSeen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final stream =
        widget.connectivityStream ??
        (system.isAndroid ? app!.networkChanges : networkChanges());
    subscription = stream.listen(_handleResults);
    ref.listenManual(excludeSSIDsProvider.select((state) => state.isNotEmpty), (
      previous,
      next,
    ) {
      if (previous != next) {
        unawaited(_updateSsid());
      }
    });
    ref.listenManual(
      locationPermissionsProvider.select(
        (permission) => permission == WifiSsidPermission.granted,
      ),
      (previous, next) {
        if (previous != next) {
          unawaited(_updateSsid());
        }
      },
    );
    // Cold start emits no connectivity event, so read the current network
    // once up front; otherwise an already-connected excluded SSID stays
    // unpublished until the next resume or network change. Deferred past
    // initState: the refresh writes providers, which initState may not do.
    // A stream result arriving first sets _streamSeen, so the deferred
    // refresh skips itself instead of re-reading after the stream.
    unawaited(Future(_refreshOnResume));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshOnResume());
    }
  }

  // A Wi-Fi to Wi-Fi switch may not move the connectivity stream, and the
  // app may have been suspended while the network changed, so re-read the
  // current network and SSID when coming back to the foreground. This is
  // what lets the direct/disconnect action restore the previous mode.
  // The rust_api network watcher covers desktop and Android only, so on
  // iOS the stream never fires and resume probes the SSID directly.
  Future<void> _refreshOnResume() async {
    // A stream result that landed before this ran already refreshed the
    // network state; do not read it a second time.
    if (_streamSeen) return;
    await _updateSsid(probeWifi: true);
  }

  void _handleResults(NetworkState state) {
    _streamSeen = true;
    _onWifi = state.wifi;
    unawaited(_updateSsid());
    widget.onConnectivityChanged?.call(state);
  }

  Future<void> _updateSsid({bool probeWifi = false}) async {
    final requestId = ++_ssidRequestId;
    // The SSID costs a blocking platform call and a location permission on
    // Android, macOS and Windows, and nothing reads it until a network is
    // excluded.
    if ((!probeWifi && !_onWifi) ||
        ref.read(safeModeProvider) ||
        ref.read(excludeSSIDsProvider).isEmpty) {
      _publishSsid(requestId, null);
      return;
    }
    try {
      final ssid = await _readSsid();
      if (probeWifi) {
        _onWifi = ssid != null;
      }
      if (_publishSsid(requestId, ssid)) {
        commonPrint.log('Wi-fi SSID: $ssid', logLevel: LogLevel.info);
      }
    } catch (error) {
      commonPrint.log(
        'Unable to read the Wi-Fi SSID: $error',
        logLevel: LogLevel.warning,
      );
      _publishSsid(requestId, null);
    }
  }

  bool _publishSsid(int requestId, String? ssid) {
    if (requestId != _ssidRequestId || !mounted) {
      return false;
    }
    ref.read(currentSSIDProvider.notifier).value = ssid;
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
