import 'package:fl_clash/core/external_controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/effective_mode.dart';
import 'package:fl_clash/providers/route_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockExternalControllerClient extends Mock
    implements ExternalControllerClient {}

class _TunnelStateNotifier extends Notifier<TunnelState?> {
  @override
  TunnelState? build() => null;

  void set(TunnelState? value) => state = value;
}

void main() {
  late _MockExternalControllerClient client;
  late NotifierProvider<_TunnelStateNotifier, TunnelState?> tunnelStateOverride;

  ProviderContainer build({
    TunnelState? tunnel = TunnelState.connected,
    Mode? live = Mode.direct,
  }) {
    client = _MockExternalControllerClient();
    when(() => client.fetchMode()).thenAnswer((_) async => live);
    tunnelStateOverride = NotifierProvider<_TunnelStateNotifier, TunnelState?>(
      _TunnelStateNotifier.new,
    );
    final container = ProviderContainer(
      overrides: [
        routeTrackerProvider.overrideWithBuild((_, _) => const RouteState()),
        tunnelStateProvider.overrideWith(
          (ref) => ref.watch(tunnelStateOverride),
        ),
        externalControllerClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    container.read(tunnelStateOverride.notifier).set(tunnel);
    container.listen(effectiveModeProvider, (_, _) {});
    return container;
  }

  Future<void> settle() async {
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  test(
    'reads the live mode from the routing core while the tunnel is up',
    () async {
      final container = build();
      await settle();

      expect(container.read(effectiveModeProvider), Mode.direct);
      expect(container.read(patchClashConfigProvider).mode, Mode.rule);
    },
  );

  test(
    'keeps the configured mode when the controller does not answer',
    () async {
      final container = build(live: null);
      await settle();

      expect(container.read(effectiveModeProvider), Mode.rule);
      verify(() => client.fetchMode()).called(1);
    },
  );

  test('does not ask the controller while the tunnel is down', () async {
    final container = build(tunnel: TunnelState.disconnected);
    await settle();

    expect(container.read(effectiveModeProvider), Mode.rule);
    verifyNever(() => client.fetchMode());
  });

  test('re-reads when the tunnel connects', () async {
    final container = build(tunnel: TunnelState.disconnected);
    await settle();
    expect(container.read(effectiveModeProvider), Mode.rule);

    container.read(tunnelStateOverride.notifier).set(TunnelState.connected);
    await settle();

    expect(container.read(effectiveModeProvider), Mode.direct);
  });

  test('follows the configured mode when it changes', () async {
    final container = build();
    await settle();
    expect(container.read(effectiveModeProvider), Mode.direct);

    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mode: Mode.global));
    await pumpEventQueue();

    expect(container.read(effectiveModeProvider), Mode.global);
  });
}
