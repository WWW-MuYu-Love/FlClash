import 'dart:async';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/external_controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod/riverpod.dart';

class MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

class _FakeExternalControllerClient extends ExternalControllerClient {
  _FakeExternalControllerClient(this.snapshot)
    : super(baseUri: Uri.parse('http://127.0.0.1:1'));

  final ExternalControllerSnapshot? snapshot;
  int fetchConnectionsCalls = 0;

  @override
  Future<ExternalControllerSnapshot?> fetchConnections() async {
    fetchConnectionsCalls++;
    return snapshot;
  }
}

const runningVersion = '0.8.96';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockCoreHandlerInterface core;

  setUpAll(() {
    core = MockCoreHandlerInterface();
    globalState.packageInfo = PackageInfo(
      appName: 'FlClash',
      packageName: 'com.follow.clash',
      version: runningVersion,
      buildNumber: '1',
    );
  });

  setUp(() => reset(core));

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('CommonAction.updateMode', () {
    test('advances through every mode and wraps back to the first', () {
      final container = buildContainer();
      final action = container.read(commonActionProvider.notifier);
      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mode: Mode.values.first));

      final seen = <Mode>[container.read(patchClashConfigProvider).mode];
      for (var i = 0; i < Mode.values.length; i++) {
        action.updateMode();
        seen.add(container.read(patchClashConfigProvider).mode);
      }

      expect(seen.sublist(0, Mode.values.length), Mode.values);
      expect(seen.last, Mode.values.first, reason: 'wraps after the last mode');
    });
  });

  group('CommonAction.updateSpeedStatistics', () {
    test('toggles the tray title flag both ways', () {
      final container = buildContainer();
      final action = container.read(commonActionProvider.notifier);
      final initial = container.read(appSettingProvider).showTrayTitle;

      action.updateSpeedStatistics();
      expect(container.read(appSettingProvider).showTrayTitle, !initial);

      action.updateSpeedStatistics();
      expect(container.read(appSettingProvider).showTrayTitle, initial);
    });
  });

  group('CommonAction.updateTraffic', () {
    test('records the sampled traffic and the running total', () async {
      final container = buildContainer();
      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(onlyStatisticsProxy: true));
      when(
        () => core.getTraffic(true),
      ).thenAnswer((_) async => const Traffic(up: 10, down: 20));
      when(
        () => core.getTotalTraffic(true),
      ).thenAnswer((_) async => const Traffic(up: 100, down: 200));

      await container.read(commonActionProvider.notifier).updateTraffic();

      expect(container.read(trafficsProvider).list.last.up, 10);
      expect(container.read(trafficsProvider).list.last.down, 20);
      expect(
        container.read(totalTrafficProvider),
        const Traffic(up: 100, down: 200),
      );
      verify(() => core.getTraffic(true)).called(1);
      verify(() => core.getTotalTraffic(true)).called(1);
    });

    test('swallows a core failure and leaves the total untouched', () async {
      final container = buildContainer();
      final before = container.read(totalTrafficProvider);
      when(() => core.getTraffic(any())).thenThrow(StateError('core down'));

      await expectLater(
        container.read(commonActionProvider.notifier).updateTraffic(),
        completes,
      );
      expect(container.read(totalTrafficProvider), before);
    });

    test('does not record a total when only the total call fails', () async {
      final container = buildContainer();
      final before = container.read(totalTrafficProvider);
      when(
        () => core.getTraffic(any()),
      ).thenAnswer((_) async => const Traffic(up: 1, down: 2));
      when(() => core.getTotalTraffic(any())).thenThrow(StateError('boom'));

      await container.read(commonActionProvider.notifier).updateTraffic();

      expect(container.read(trafficsProvider).list.last.up, 1);
      expect(container.read(totalTrafficProvider), before);
    });

    test(
      'drops concurrent in-flight updates while one is in progress',
      () async {
        final container = buildContainer();
        final completer = Completer<Traffic>();
        when(() => core.getTraffic(any())).thenAnswer((_) => completer.future);
        when(
          () => core.getTotalTraffic(any()),
        ).thenAnswer((_) => completer.future);

        final first = container
            .read(commonActionProvider.notifier)
            .updateTraffic();
        final second = container
            .read(commonActionProvider.notifier)
            .updateTraffic();

        await expectLater(second, completes);
        completer.complete(const Traffic(up: 5, down: 10));
        await first;

        verify(() => core.getTraffic(any())).called(1);
        verify(() => core.getTotalTraffic(any())).called(1);
      },
    );
  });

  group('CommonAction.updateTraffic via the external controller', () {
    const snapshot = ExternalControllerSnapshot(
      uploadTotal: 5000,
      downloadTotal: 9000,
      connections: [],
    );

    (ProviderContainer, _FakeExternalControllerClient) buildExternalContainer(
      ExternalControllerSnapshot? snapshot,
    ) {
      final client = _FakeExternalControllerClient(snapshot);
      final container = ProviderContainer(
        overrides: [
          coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
          externalControllerClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);
      return (container, client);
    }

    test('takes the totals from the core and never asks 9090', () async {
      final (container, client) = buildExternalContainer(snapshot);
      when(
        () => core.getTraffic(any()),
      ).thenAnswer((_) async => const Traffic(up: 10, down: 20));
      when(
        () => core.getTotalTraffic(any()),
      ).thenAnswer((_) async => const Traffic(up: 100, down: 200));

      await container.read(commonActionProvider.notifier).updateTraffic();

      expect(container.read(trafficsProvider).list.last.up, 10);
      expect(
        container.read(totalTrafficProvider),
        const Traffic(up: 100, down: 200),
      );
      expect(client.fetchConnectionsCalls, 0);
      verify(() => core.getTraffic(any())).called(1);
      verify(() => core.getTotalTraffic(any())).called(1);
    });

    test('falls back to 9090 when the core fails', () async {
      final (container, client) = buildExternalContainer(snapshot);
      when(() => core.getTraffic(any())).thenThrow(StateError('core down'));
      when(
        () => core.getTotalTraffic(any()),
      ).thenThrow(StateError('core down'));

      await container.read(commonActionProvider.notifier).updateTraffic();

      expect(
        container.read(totalTrafficProvider),
        const Traffic(up: 5000, down: 9000),
      );
      expect(client.fetchConnectionsCalls, 1);
    });
  });

  group('CommonAction.updateTraffic XPC backoff', () {
    const snapshot = ExternalControllerSnapshot(
      uploadTotal: 5000,
      downloadTotal: 9000,
      connections: [],
    );

    const emptyResponse = CoreMethodException(
      code: 'empty_response',
      message: 'empty network extension response',
    );

    (ProviderContainer, _FakeExternalControllerClient, CommonAction)
    buildBackoffContainer() {
      final client = _FakeExternalControllerClient(snapshot);
      final container = ProviderContainer(
        overrides: [
          coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
          externalControllerClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);
      return (container, client, container.read(commonActionProvider.notifier));
    }

    test(
      'skips XPC for a minute after an empty response and uses 9090',
      () async {
        final (container, client, action) = buildBackoffContainer();
        var now = DateTime(2026, 11, 14);
        action.clock = () => now;
        when(() => core.getTraffic(any())).thenThrow(emptyResponse);
        when(() => core.getTotalTraffic(any())).thenThrow(emptyResponse);

        await action.updateTraffic();
        expect(client.fetchConnectionsCalls, 1);

        now = now.add(const Duration(seconds: 10));
        await action.updateTraffic();
        expect(client.fetchConnectionsCalls, 2);
        expect(
          container.read(totalTrafficProvider),
          const Traffic(up: 5000, down: 9000),
        );
        verify(() => core.getTraffic(any())).called(1);
        verify(() => core.getTotalTraffic(any())).called(1);
      },
    );

    test('retries XPC after the backoff window expires', () async {
      final (_, client, action) = buildBackoffContainer();
      var now = DateTime(2026, 11, 14);
      action.clock = () => now;
      when(() => core.getTraffic(any())).thenThrow(emptyResponse);
      when(() => core.getTotalTraffic(any())).thenThrow(emptyResponse);

      await action.updateTraffic();
      expect(client.fetchConnectionsCalls, 1);

      now = now.add(const Duration(seconds: 61));
      await action.updateTraffic();
      expect(client.fetchConnectionsCalls, 2);
      verify(() => core.getTraffic(any())).called(2);
      verify(() => core.getTotalTraffic(any())).called(2);
    });

    test('an XPC success clears the backoff at once', () async {
      final (_, client, action) = buildBackoffContainer();
      var now = DateTime(2026, 11, 14);
      action.clock = () => now;
      when(() => core.getTraffic(any())).thenThrow(emptyResponse);
      when(() => core.getTotalTraffic(any())).thenThrow(emptyResponse);

      await action.updateTraffic();
      expect(client.fetchConnectionsCalls, 1);

      now = now.add(const Duration(seconds: 61));
      when(
        () => core.getTraffic(any()),
      ).thenAnswer((_) async => const Traffic(up: 10, down: 20));
      when(
        () => core.getTotalTraffic(any()),
      ).thenAnswer((_) async => const Traffic(up: 100, down: 200));
      await action.updateTraffic();
      expect(client.fetchConnectionsCalls, 1);

      await action.updateTraffic();
      expect(client.fetchConnectionsCalls, 1);
      verify(() => core.getTraffic(any())).called(3);
      verify(() => core.getTotalTraffic(any())).called(3);
    });

    test('other errors do not start the backoff', () async {
      final (_, _, action) = buildBackoffContainer();
      var now = DateTime(2026, 11, 14);
      action.clock = () => now;
      const transportError = CoreMethodException(
        code: 'transport_error',
        message: 'transport error',
      );
      when(() => core.getTraffic(any())).thenThrow(transportError);
      when(() => core.getTotalTraffic(any())).thenThrow(transportError);

      await action.updateTraffic();

      now = now.add(const Duration(seconds: 10));
      await action.updateTraffic();
      verify(() => core.getTraffic(any())).called(2);
      verify(() => core.getTotalTraffic(any())).called(2);
    });
  });

  group('CommonAction.autoCheckUpdate', () {
    test('returns without a network call when the setting is off', () async {
      final container = buildContainer();
      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(autoCheckUpdate: false));

      await expectLater(
        container.read(commonActionProvider.notifier).autoCheckUpdate(),
        completion(isFalse),
      );
    });
  });
}
