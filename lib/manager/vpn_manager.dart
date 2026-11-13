import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/tile.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/banner.dart';

class VpnManager extends ConsumerStatefulWidget {
  final Widget child;

  const VpnManager({super.key, required this.child});

  @override
  ConsumerState<VpnManager> createState() => _VpnContainerState();
}

class _VpnContainerState extends ConsumerState<VpnManager> with TileListener {
  @override
  void initState() {
    super.initState();
    tile?.addListener(this);
    ref.listenManual(vpnOptionsProvider.select((state) => state.value), (
      prev,
      next,
    ) {
      final running = ref.read(runningVpnOptionsProvider);
      if (next == null || prev == null || running == null) {
        return;
      }
      if (running.effective == next.effective) {
        return;
      }
      if (prev.copyWith(enable: next.enable) == next) {
        unawaited(_toggleTunnelOnly(prev: prev, next: next));
        return;
      }
      _showRestartTip();
    });
    // A failed tunnel start is otherwise silent: the dashboard shows the
    // core running while the system VPN never connects.
    ref.listenManual(tunnelErrorProvider, (prev, next) {
      if (next != null && next != prev) {
        dialogs.showBanner(
          tunnelStartFailureMessage(next, currentAppLocalizations),
          level: BannerLevel.error,
        );
      }
    });
  }

  @override
  void dispose() {
    tile?.removeListener(this);
    super.dispose();
  }

  @override
  void onSyncRunningState(bool running) {
    if (!ref.read(initProvider)) {
      return;
    }
    if (running) {
      ref
          .read(vpnSettingProvider.notifier)
          .update((state) => state.copyWith(enable: true));
      if (!ref.read(isStartProvider)) {
        unawaited(ref.read(setupActionProvider.notifier).setRunning(true));
      }
      return;
    }
    if (!ref.read(isStartProvider) ||
        !ref.read(vpnSettingProvider).enable ||
        ref.read(suspendProvider)) {
      return;
    }
    // The tunnel went away; the Core keeps running. The switch flip hands
    // its listeners over to the App core, so only the tunnel stops.
    ref
        .read(vpnSettingProvider.notifier)
        .update((state) => state.copyWith(enable: false));
  }

  void _showRestartTip() {
    dialogs.showBanner(
      currentAppLocalizations.vpnConfigChangeDetected,
      level: BannerLevel.warning,
      onTap: () {
        unawaited(ref.read(setupActionProvider.notifier).restartVpn());
      },
    );
  }

  Future<void> _toggleTunnelOnly({
    required VpnOptions prev,
    required VpnOptions next,
  }) async {
    final bool handled;
    try {
      handled = await ref
          .read(setupActionProvider.notifier)
          .setTunnelEnabled(next.enable);
    } catch (error, s) {
      commonPrint.log(
        'toggleTunnelOnly ===> ${compactError(error)}, $s',
        logLevel: LogLevel.error,
      );
      if (next.enable) {
        // The tunnel never started: put the switch back where it was.
        ref
            .read(vpnSettingProvider.notifier)
            .update((state) => state.copyWith(enable: prev.enable));
      }
      dialogs.showBanner(
        userFacingErrorMessage(error, currentAppLocalizations),
        level: BannerLevel.error,
      );
      return;
    }
    if (!handled) {
      _showRestartTip();
      return;
    }
    ref.read(runningVpnOptionsProvider.notifier).value = next;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
