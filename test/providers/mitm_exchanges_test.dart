import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/external_controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/mitm.dart';
import 'package:riverpod/riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

class _MockExternalControllerClient extends Mock
    implements ExternalControllerClient {}

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

final _start = DateTime.utc(2026, 10, 29);

MitmExchangeList _list({required bool closed, required bool pending}) =>
    MitmExchangeList(
      capturing: true,
      closed: closed,
      exchanges: [
        MitmExchangeSummary(
          id: 1,
          start: _start,
          pending: pending,
          method: 'GET',
          url: 'https://a.test/',
        ),
      ],
    );

void main() {
  testWidgets('requests are fetched again until the host settles', (
    tester,
  ) async {
    final answers = [
      _list(closed: false, pending: false),
      _list(closed: true, pending: true),
      _list(closed: true, pending: false),
    ];
    var calls = 0;
    final core = _MockCoreHandlerInterface();
    final client = _MockExternalControllerClient();
    when(
      () => client.fetchMitmExchangesByHost('a.test'),
    ).thenAnswer((_) async => null);
    when(
      () => core.getMitmExchangesByHost('a.test', route: CoreRoute.app),
    ).thenAnswer((_) async => answers[(calls++).clamp(0, answers.length - 1)]);
    final container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        externalControllerClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    container.listen(mitmExchangesProvider('a.test'), (_, _) {});

    for (var second = 0; second < 12; second++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(calls, answers.length);
    expect(container.read(mitmExchangesProvider('a.test')).value, answers.last);
  });

  ProviderContainer routedContainer({required _MockCoreHandlerInterface core}) {
    final client = _MockExternalControllerClient();
    when(
      () => client.fetchMitmExchangesByHost('a.test'),
    ).thenAnswer((_) async => null);
    when(() => client.fetchMitmExchange(any())).thenAnswer((_) async => null);
    when(
      () => client.fetchMitmBody(any(), response: any(named: 'response')),
    ).thenAnswer((_) async => null);
    final scope = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        externalControllerClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(scope.dispose);
    scope.read(runningVpnOptionsProvider.notifier).value = _runningVpnOptions;
    return scope;
  }

  test('falls back to the app core when 9090 answers nothing', () async {
    final core = _MockCoreHandlerInterface();
    final appList = _list(closed: true, pending: false);
    when(
      () => core.getMitmExchangesByHost('a.test', route: CoreRoute.app),
    ).thenAnswer((_) async => appList);
    final scope = routedContainer(core: core);

    final list = await scope.read(mitmExchangesProvider('a.test').future);

    expect(list, appList);
    verify(
      () => core.getMitmExchangesByHost('a.test', route: CoreRoute.app),
    ).called(1);
  });

  test(
    'raw body falls back to the app core when 9090 answers nothing',
    () async {
      final core = _MockCoreHandlerInterface();
      final client = _MockExternalControllerClient();
      when(
        () => client.fetchMitmBody(1, response: true),
      ).thenAnswer((_) async => null);
      const appBody = MitmBody(data: 'd29ybGQ=');
      when(
        () => core.getMitmBody(1, response: true, route: CoreRoute.app),
      ).thenAnswer((_) async => appBody);

      final body = await readRoutedMitmBody(
        client: client,
        coreHandler: CoreController.scoped(core),
        id: 1,
        response: true,
      );

      expect(body, appBody);
      verify(
        () => core.getMitmBody(1, response: true, route: CoreRoute.app),
      ).called(1);
    },
  );
}
