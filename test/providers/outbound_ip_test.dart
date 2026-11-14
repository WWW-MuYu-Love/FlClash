import 'dart:async';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/external_controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/route_state.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';

class _MockCore extends Mock implements CoreHandlerInterface {}

class _MockExternalControllerClient extends Mock
    implements ExternalControllerClient {}

const _answer = OutboundIpResult(
  url: 'https://www.cloudflare.com/cdn-cgi/trace',
  body: 'ip=2.2.2.2\nloc=US\n',
  chains: ['HK-01'],
  coreEpoch: 1,
  routeVersion: 1,
);

const _runningVpnOptions = VpnOptions(
  enable: true,
  port: 7890,
  ipv6: false,
  dnsHijacking: false,
  accessControlProps: AccessControlProps(),
  allowBypass: false,
  systemProxy: false,
  bypassDomain: [],
  stack: 'gvisor',
);

void main() {
  setUpAll(() => registerFallbackValue(const OutboundIpParams(timeout: 0)));

  late _MockCore core;

  setUp(() => core = _MockCore());

  ProviderContainer build({bool proxied = true}) {
    final client = _MockExternalControllerClient();
    when(
      () => client.fetchOutboundIp(any()),
    ).thenAnswer((_) => Future<OutboundIpResult?>.value());
    final container = ProviderContainer(
      overrides: [
        routeTrackerProvider.overrideWithBuild(
          (_, _) => RouteState(
            coreEpoch: 1,
            routeVersion: 1,
            hostEpoch: 1,
            proxied: proxied,
            synced: true,
            live: true,
          ),
        ),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        externalControllerClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    container.listen(outboundIpProbeProvider, (_, _) {});
    return container;
  }

  (ProviderContainer, _MockExternalControllerClient) runningBuild({
    OutboundIpResult? controllerAnswer,
  }) {
    final client = _MockExternalControllerClient();
    when(
      () => client.fetchOutboundIp(any()),
    ).thenAnswer((_) => Future<OutboundIpResult?>.value(controllerAnswer));
    final container = ProviderContainer(
      overrides: [
        routeTrackerProvider.overrideWithBuild(
          (_, _) => const RouteState(
            coreEpoch: 1,
            routeVersion: 1,
            hostEpoch: 1,
            proxied: true,
            synced: true,
            live: true,
          ),
        ),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        externalControllerClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    container.read(runningVpnOptionsProvider.notifier).value =
        _runningVpnOptions;
    container.listen(outboundIpProbeProvider, (_, _) {});
    return (container, client);
  }

  Future<OutboundIpParams> asked() async {
    await pumpEventQueue();
    return verify(
          () => core.outboundIp(captureAny(), route: CoreRoute.app),
        ).captured.single
        as OutboundIpParams;
  }

  test(
    'asks the Core for the address the current route exits through',
    () async {
      when(
        () => core.outboundIp(any(), route: CoreRoute.app),
      ).thenAnswer((_) async => _answer);
      final container = build();

      container.read(outboundIpProbeProvider.notifier).watch(routedOutbound);

      final params = await asked();
      expect(params.proxyName, isEmpty);
      expect(params.urls, ipInfoSources.keys.toList());
      final entry = container
          .read(outboundIpProbeProvider)
          .entryOf(routedOutbound);
      expect(entry.phase, ProbePhase.fresh);
      expect(entry.value?.ip, '2.2.2.2');
    },
  );

  test('pins the direct outbound while the proxy is off', () async {
    when(
      () => core.outboundIp(any(), route: CoreRoute.app),
    ).thenAnswer((_) async => _answer);
    final container = build(proxied: false);

    container.read(outboundIpProbeProvider.notifier).watch(routedOutbound);

    expect((await asked()).proxyName, directOutbound);
  });

  test('looks a node up through itself', () async {
    when(
      () => core.outboundIp(any(), route: CoreRoute.app),
    ).thenAnswer((_) async => _answer);
    final container = build();

    container.read(outboundIpProbeProvider.notifier).watch('HK-01');

    expect((await asked()).proxyName, 'HK-01');
    expect(
      container.read(outboundIpProbeProvider).valueOf('HK-01')?.countryCode,
      'US',
    );
  });

  test('the routed answer fills in the node it left through', () async {
    when(() => core.outboundIp(any(), route: CoreRoute.app)).thenAnswer(
      (_) async => const OutboundIpResult(
        url: 'https://www.cloudflare.com/cdn-cgi/trace',
        body: 'ip=2.2.2.2\nloc=US\n',
        chains: ['HK-01', 'Balance', 'Proxy'],
        coreEpoch: 1,
        routeVersion: 1,
        hits: [RouteHit(host: 'www.cloudflare.com:443', exit: 'Balance')],
        nodeHits: [
          RouteHit(
            host: 'www.cloudflare.com:443',
            proxy: 'HK-01',
            exit: 'HK-01',
          ),
        ],
      ),
    );
    final container = build();
    final probe = container.read(outboundIpProbeProvider.notifier);

    probe.watch(routedOutbound);
    await pumpEventQueue();
    probe.watch('HK-01');
    await pumpEventQueue();

    verify(() => core.outboundIp(any(), route: CoreRoute.app)).called(1);
    final entry = container.read(outboundIpProbeProvider).entryOf('HK-01');
    expect(entry.phase, ProbePhase.fresh);
    expect(entry.value?.ip, '2.2.2.2');
    expect(entry.stamp?.hits, const [
      RouteHit(host: 'www.cloudflare.com:443', proxy: 'HK-01', exit: 'HK-01'),
    ]);
  });

  test('uses the XPC answer directly and never asks 9090', () async {
    when(() => core.outboundIp(any())).thenAnswer((_) async => _answer);
    final (container, client) = runningBuild(
      controllerAnswer: const OutboundIpResult(
        url: 'https://www.cloudflare.com/cdn-cgi/trace',
        body: 'ip=3.3.3.3\nloc=US\n',
        chains: ['HK-01'],
        coreEpoch: 1,
        routeVersion: 1,
      ),
    );

    container.read(outboundIpProbeProvider.notifier).watch(routedOutbound);
    await pumpEventQueue();

    verify(() => core.outboundIp(any())).called(1);
    verifyNever(() => client.fetchOutboundIp(any()));
    verifyNever(() => core.outboundIp(any(), route: CoreRoute.app));
    expect(
      container.read(outboundIpProbeProvider).valueOf(routedOutbound)?.ip,
      '2.2.2.2',
    );
  });

  test('falls back to 9090 when XPC throws', () async {
    when(() => core.outboundIp(any())).thenThrow(
      const CoreMethodException(code: 'empty_response', message: 'empty'),
    );
    final (container, client) = runningBuild(controllerAnswer: _answer);

    container.read(outboundIpProbeProvider.notifier).watch(routedOutbound);
    await pumpEventQueue();

    verify(() => client.fetchOutboundIp(any())).called(1);
    verifyNever(() => core.outboundIp(any(), route: CoreRoute.app));
    expect(
      container.read(outboundIpProbeProvider).valueOf(routedOutbound)?.ip,
      '2.2.2.2',
    );
  });

  testWidgets('falls back to 9090 when the XPC attempt times out', (
    tester,
  ) async {
    when(
      () => core.outboundIp(any()),
    ).thenAnswer((_) => Completer<OutboundIpResult>().future);
    final (container, client) = runningBuild(controllerAnswer: _answer);

    container.read(outboundIpProbeProvider.notifier).watch(routedOutbound);
    await tester.pump();
    await tester.pump(outboundIpXpcAttemptDuration);
    await tester.pump();

    verify(() => client.fetchOutboundIp(any())).called(1);
    verifyNever(() => core.outboundIp(any(), route: CoreRoute.app));
    expect(
      container.read(outboundIpProbeProvider).valueOf(routedOutbound)?.ip,
      '2.2.2.2',
    );
    await tester.pump(probeThrottleDuration);
  });

  test('does not try XPC when the tunnel is down', () async {
    when(
      () => core.outboundIp(any(), route: CoreRoute.app),
    ).thenAnswer((_) async => _answer);
    final container = build();

    container.read(outboundIpProbeProvider.notifier).watch(routedOutbound);
    await pumpEventQueue();

    verifyNever(() => core.outboundIp(any()));
    verify(() => core.outboundIp(any(), route: CoreRoute.app)).called(1);
  });

  test('falls back to the app core when 9090 answers nothing', () async {
    when(
      () => core.outboundIp(any(), route: CoreRoute.app),
    ).thenAnswer((_) async => _answer);
    final container = build();

    container.read(outboundIpProbeProvider.notifier).watch(routedOutbound);
    await pumpEventQueue();

    verify(() => core.outboundIp(any(), route: CoreRoute.app)).called(1);
    final entry = container
        .read(outboundIpProbeProvider)
        .entryOf(routedOutbound);
    expect(entry.phase, ProbePhase.fresh);
    expect(entry.value?.ip, '2.2.2.2');
  });

  test('falls back to the app core when XPC and 9090 answer nothing', () async {
    when(() => core.outboundIp(any())).thenThrow(
      const CoreMethodException(code: 'empty_response', message: 'empty'),
    );
    when(
      () => core.outboundIp(any(), route: CoreRoute.app),
    ).thenAnswer((_) async => _answer);
    final (container, _) = runningBuild();

    container.read(outboundIpProbeProvider.notifier).watch(routedOutbound);
    await pumpEventQueue();

    verify(() => core.outboundIp(any())).called(1);
    verify(() => core.outboundIp(any(), route: CoreRoute.app)).called(1);
    expect(
      container.read(outboundIpProbeProvider).valueOf(routedOutbound)?.ip,
      '2.2.2.2',
    );
  });

  test('a Core error is a failure until it is refreshed', () async {
    when(() => core.outboundIp(any(), route: CoreRoute.app)).thenAnswer(
      (_) async => const OutboundIpResult(
        error: 'timeout',
        coreEpoch: 1,
        routeVersion: 1,
      ),
    );
    final container = build();
    final probe = container.read(outboundIpProbeProvider.notifier);

    probe.watch(routedOutbound);
    await pumpEventQueue();

    expect(
      container.read(outboundIpProbeProvider).entryOf(routedOutbound).phase,
      ProbePhase.failed,
    );
    verify(() => core.outboundIp(any(), route: CoreRoute.app)).called(1);

    probe.refresh([routedOutbound]);
    await pumpEventQueue();

    verify(() => core.outboundIp(any(), route: CoreRoute.app)).called(1);
  });
}
