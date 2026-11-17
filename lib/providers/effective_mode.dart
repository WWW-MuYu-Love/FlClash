import 'dart:async';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app.dart';
import 'config.dart';
import 'core.dart';
import 'route_state.dart';

part 'generated/effective_mode.g.dart';

/// The mode the routing core actually runs; while the tunnel is up it
/// asks the core behind 9090, whose mode an SSID override can change.
@Riverpod(keepAlive: true)
class EffectiveMode extends _$EffectiveMode {
  int _run = 0;

  @override
  Mode build() {
    ref.listen(
      patchClashConfigProvider.select((state) => state.mode),
      (_, mode) => state = mode,
    );
    ref.listen(appVisibleProvider, (_, visible) {
      if (visible) {
        unawaited(refresh());
      }
    });
    ref.listen(tunnelStateProvider, (previous, next) {
      if (previous != next) {
        unawaited(refresh());
      }
    });
    ref.listen(routeTrackerProvider, (previous, next) {
      if (previous != null && _moved(previous, next)) {
        unawaited(refresh());
      }
    });
    unawaited(refresh());
    return ref.read(patchClashConfigProvider).mode;
  }

  /// Re-reads the live mode; a failed read keeps the configured value.
  Future<void> refresh() => _read();

  Future<void> _read() async {
    if (!ref.read(appVisibleProvider)) {
      return;
    }
    final run = ++_run;
    final configured = ref.read(patchClashConfigProvider).mode;
    final live = await _liveMode();
    if (!ref.mounted || run != _run) {
      return;
    }
    state = live ?? configured;
  }

  Future<Mode?> _liveMode() async {
    if (ref.read(tunnelStateProvider) != TunnelState.connected) {
      return null;
    }
    return ref.read(externalControllerClientProvider).fetchMode();
  }
}

bool _moved(RouteState previous, RouteState next) =>
    next.routeVersion != previous.routeVersion ||
    next.coreEpoch != previous.coreEpoch ||
    next.resumes != previous.resumes ||
    next.proxied != previous.proxied;
