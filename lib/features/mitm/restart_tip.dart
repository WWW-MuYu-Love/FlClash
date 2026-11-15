import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/banner.dart';

/// Shows the restart banner; the VPN text merges with the manager's own.
void showMitmRestartTip(WidgetRef ref, String message) {
  final restartable =
      ref.read(isStartProvider) &&
      (!system.isIOS || ref.read(runningVpnOptionsProvider)?.enable == true) &&
      ref.read(patchClashConfigProvider).mitm.enable;
  if (!restartable) {
    return;
  }
  dialogs.showBanner(
    message,
    level: BannerLevel.warning,
    onTap: () {
      unawaited(ref.read(setupActionProvider.notifier).restartVpn());
    },
  );
}
