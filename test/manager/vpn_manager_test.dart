import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/manager/vpn_manager.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/banner.dart';
import 'package:prism_ui/prism_ui.dart';
import '../helpers/test_app.dart';

class _RestartRecordingSetupAction extends SetupAction {
  int restarts = 0;
  int tunnelToggles = 0;
  bool? lastTunnelEnabled;
  // False mirrors the real method off iOS; set true to simulate the iOS
  // fast path.
  bool tunnelToggleHandled = false;
  Exception? tunnelToggleError;

  @override
  Future<void> restartVpn() async {
    restarts++;
  }

  @override
  Future<bool> setTunnelEnabled(bool enable) async {
    tunnelToggles++;
    lastTunnelEnabled = enable;
    final error = tunnelToggleError;
    if (error != null) {
      throw error;
    }
    return tunnelToggleHandled;
  }
}

void main() {
  late ProviderContainer container;
  late _RestartRecordingSetupAction setupAction;

  setUp(() {
    setupAction = _RestartRecordingSetupAction();
    container = ProviderContainer(
      overrides: [
        setupActionProvider.overrideWith(() => setupAction),
        // Bypassing private addresses computes the routes in Isolate.run, which
        // the fake clock never lets finish.
        networkSettingProvider.overrideWithBuild(
          (_, _) => const NetworkProps(bypassPrivateRoute: false),
        ),
      ],
    );
    globalState.container = container;
  });

  tearDown(() => container.dispose());

  Future<void> pumpVpnManager(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: HostApp(
          navigatorKey: globalState.navigatorKey,
          builder: (_, child) {
            return BannerHost(
              stacked: false,
              topInset: 0,
              child: VpnManager(child: child!),
            );
          },
          home: const SizedBox(),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  Future<void> outlastTip(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 7));
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> drainTimers(WidgetTester tester) async {
    await outlastTip(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  }

  void startService() {
    container.read(runningVpnOptionsProvider.notifier).value = container
        .read(vpnOptionsProvider)
        .requireValue;
  }

  void updateVpn(VpnProps Function(VpnProps state) update) {
    container.read(vpnSettingProvider.notifier).update(update);
  }

  Finder tip() => find.text(currentAppLocalizations.vpnConfigChangeDetected);

  testWidgets('a change the running service reads asks for a restart', (
    tester,
  ) async {
    await pumpVpnManager(tester);
    startService();

    updateVpn((state) => state.copyWith(ipv6: !state.ipv6));
    await settle(tester);
    expect(tip(), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(tip());
    await tester.pump();
    expect(setupAction.restarts, 1);
    await drainTimers(tester);
  });

  testWidgets('turning VPN off while the service runs asks for a restart', (
    tester,
  ) async {
    await pumpVpnManager(tester);
    startService();

    updateVpn((state) => state.copyWith(enable: false));
    await settle(tester);
    expect(tip(), findsOneWidget);
    expect(setupAction.restarts, 0);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(tip());
    await tester.pump();
    expect(setupAction.restarts, 1);
    await drainTimers(tester);
  });

  testWidgets('flipping the VPN switch off toggles only the tunnel', (
    tester,
  ) async {
    setupAction.tunnelToggleHandled = true;
    await pumpVpnManager(tester);
    startService();

    updateVpn((state) => state.copyWith(enable: false));
    await settle(tester);

    expect(tip(), findsNothing);
    expect(setupAction.tunnelToggles, 1);
    expect(setupAction.lastTunnelEnabled, isFalse);
    expect(setupAction.restarts, 0);
    expect(container.read(runningVpnOptionsProvider)?.enable, isFalse);
    await drainTimers(tester);
  });

  testWidgets('flipping the VPN switch on toggles only the tunnel', (
    tester,
  ) async {
    setupAction.tunnelToggleHandled = true;
    await pumpVpnManager(tester);
    updateVpn((state) => state.copyWith(enable: false));
    await settle(tester);
    startService();

    updateVpn((state) => state.copyWith(enable: true));
    await settle(tester);

    expect(tip(), findsNothing);
    expect(setupAction.tunnelToggles, 1);
    expect(setupAction.lastTunnelEnabled, isTrue);
    expect(setupAction.restarts, 0);
    expect(container.read(runningVpnOptionsProvider)?.enable, isTrue);
    await drainTimers(tester);
  });

  testWidgets('an enable flip with another change still asks for a restart', (
    tester,
  ) async {
    setupAction.tunnelToggleHandled = true;
    await pumpVpnManager(tester);
    startService();

    updateVpn((state) => state.copyWith(enable: false, ipv6: !state.ipv6));
    await settle(tester);

    expect(tip(), findsOneWidget);
    expect(setupAction.tunnelToggles, 0);
    await drainTimers(tester);
  });

  testWidgets('a failed tunnel start puts the switch back', (tester) async {
    setupAction.tunnelToggleHandled = true;
    setupAction.tunnelToggleError = const CoreMethodException(
      code: 'service_refused',
      message: 'The iOS service did not start',
    );
    await pumpVpnManager(tester);
    updateVpn((state) => state.copyWith(enable: false));
    await settle(tester);
    startService();

    updateVpn((state) => state.copyWith(enable: true));
    await settle(tester);
    await settle(tester);

    expect(container.read(vpnSettingProvider).enable, isFalse);
    expect(find.text('The iOS service did not start'), findsOneWidget);
    expect(tip(), findsNothing);
    expect(setupAction.tunnelToggles, 1);
    expect(setupAction.restarts, 0);
    await drainTimers(tester);
  });

  testWidgets('a failed tunnel stop leaves the switch off', (tester) async {
    setupAction.tunnelToggleHandled = true;
    setupAction.tunnelToggleError = const CoreMethodException(
      code: 'service_refused',
      message: 'The mobile service did not stop',
    );
    await pumpVpnManager(tester);
    startService();

    updateVpn((state) => state.copyWith(enable: false));
    await settle(tester);
    await settle(tester);

    expect(container.read(vpnSettingProvider).enable, isFalse);
    expect(find.text('The mobile service did not stop'), findsOneWidget);
    expect(tip(), findsNothing);
    expect(setupAction.tunnelToggles, 1);
    await drainTimers(tester);
  });

  testWidgets('later changes measure against the toggled options', (
    tester,
  ) async {
    setupAction.tunnelToggleHandled = true;
    await pumpVpnManager(tester);
    startService();

    updateVpn((state) => state.copyWith(enable: false));
    await settle(tester);
    expect(setupAction.tunnelToggles, 1);

    updateVpn((state) => state.copyWith(ipv6: !state.ipv6));
    await settle(tester);

    expect(tip(), findsNothing);
    await drainTimers(tester);
  });

  testWidgets('a mixed port change asks for a restart under a system proxy', (
    tester,
  ) async {
    await pumpVpnManager(tester);
    startService();

    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mixedPort: state.mixedPort + 1));
    await settle(tester);

    expect(tip(), findsOneWidget);
    await drainTimers(tester);
  });

  testWidgets('a route change asks once its routes are computed', (
    tester,
  ) async {
    await pumpVpnManager(tester);
    startService();

    container
        .read(patchClashConfigProvider.notifier)
        .update(
          (state) => state.copyWith(
            tun: state.tun.copyWith(routeAddress: const ['10.0.0.0/8']),
          ),
        );
    await tester.pump();
    expect(container.read(vpnOptionsProvider).isLoading, isTrue);
    expect(tip(), findsNothing);

    for (var i = 0; i < 100 && tip().evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(tip(), findsOneWidget);
    await drainTimers(tester);
  });

  testWidgets('no tip while no service is running', (tester) async {
    await pumpVpnManager(tester);

    updateVpn((state) => state.copyWith(ipv6: !state.ipv6));
    await settle(tester);

    expect(tip(), findsNothing);
    await drainTimers(tester);
  });

  testWidgets('no tip for what the service never reads', (tester) async {
    await pumpVpnManager(tester);
    startService();

    updateVpn(
      (state) => state.copyWith(
        accessControlProps: state.accessControlProps.copyWith(
          sort: AccessSortType.name,
          isFilterSystemApp: !state.accessControlProps.isFilterSystemApp,
        ),
      ),
    );
    await settle(tester);

    expect(tip(), findsNothing);
    await drainTimers(tester);
  });

  testWidgets('changing back to what the service runs asks for nothing', (
    tester,
  ) async {
    await pumpVpnManager(tester);
    startService();

    updateVpn((state) => state.copyWith(ipv6: !state.ipv6));
    await settle(tester);
    expect(tip(), findsOneWidget);
    await outlastTip(tester);
    expect(tip(), findsNothing);

    updateVpn((state) => state.copyWith(ipv6: !state.ipv6));
    await settle(tester);

    expect(tip(), findsNothing);
    await drainTimers(tester);
  });

  testWidgets('a restart measures later changes against the new options', (
    tester,
  ) async {
    await pumpVpnManager(tester);
    startService();
    updateVpn((state) => state.copyWith(ipv6: !state.ipv6));
    await settle(tester);
    await outlastTip(tester);
    expect(tip(), findsNothing);

    startService();
    updateVpn((state) => state.copyWith(ipv6: !state.ipv6));
    await settle(tester);

    expect(tip(), findsOneWidget);
    await drainTimers(tester);
  });
}
