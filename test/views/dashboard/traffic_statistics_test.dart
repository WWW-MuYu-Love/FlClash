import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/traffic_statistics.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/widgets/traffic_statistics.dart';
import 'package:fl_clash/views/traffic_statistics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/host_scaffold.dart';
import '../../helpers/test_app.dart';

const _size = Size(400, 800);

TrafficStatisticsData _data({int count = 3}) {
  final start = DateTime(2026, 11, 19);
  return TrafficStatisticsData(
    range: TrafficStatisticsRange.day,
    start: start,
    end: start.add(const Duration(hours: 10)),
    count: count,
    upload: 1500,
    download: 2500,
    directUpload: 500,
    directDownload: 500,
    trend: [
      TrafficStatisticsBucket(start: start, upload: 100, download: 200),
      TrafficStatisticsBucket(
        start: start.add(const Duration(hours: 1)),
        upload: 1400,
        download: 2300,
      ),
    ],
    ruleHits: const [
      TrafficStatisticsRank(label: 'RULE-SET', bytes: 3000, hits: 2),
      TrafficStatisticsRank(label: 'DIRECT', bytes: 1000, hits: 1),
    ],
    domains: const [
      TrafficStatisticsRank(label: 'example.com', bytes: 3000, hits: 2),
      TrafficStatisticsRank(label: 'other.test', bytes: 1000, hits: 1),
    ],
    processes: const [
      TrafficStatisticsRank(label: 'Safari', bytes: 3000, hits: 2),
    ],
    proxies: const [
      TrafficStatisticsRank(label: 'Node-A', bytes: 3000, hits: 2),
    ],
    profiles: const [
      TrafficStatisticsRank(label: 'Default', bytes: 4000, hits: 3),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  ProviderContainer createContainer(TrafficStatisticsData data) {
    return ProviderContainer(
      overrides: [
        for (final range in TrafficStatisticsRange.values)
          trafficStatisticsProvider(range).overrideWith((_) async => data),
      ],
    );
  }

  setUp(() {
    container = createContainer(_data());
    globalState.container = container;
  });

  tearDown(() => container.dispose());

  Future<void> pumpWidget(WidgetTester tester, Widget child) async {
    container.read(viewSizeProvider.notifier).value = _size;
    tester.view.physicalSize = _size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(child: HostScaffold(body: child)),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> teardownWidget(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('card shows today total, upload and download', (tester) async {
    await pumpWidget(tester, const TrafficStatisticsCard());

    expect(find.text('Traffic statistics'), findsOneWidget);
    expect(find.text((4000).traffic.show), findsOneWidget);
    expect(find.textContaining((1500).traffic.show), findsOneWidget);
    expect(find.textContaining((2500).traffic.show), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);

    await teardownWidget(tester);
  });

  testWidgets('card tap opens the statistics page', (tester) async {
    await pumpWidget(tester, const TrafficStatisticsCard());

    await tester.tap(find.byType(TrafficStatisticsCard));
    await tester.pumpAndSettle();

    expect(find.byType(TrafficStatisticsView), findsOneWidget);

    await teardownWidget(tester);
  });

  testWidgets('page shows all four sections with data', (tester) async {
    await pumpWidget(tester, const TrafficStatisticsView());

    expect(find.text('Traffic statistics'), findsWidgets);
    expect(find.text('Day'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Trend'), findsOneWidget);
    expect(find.text('Rule hits'), findsOneWidget);
    expect(find.text('Rankings'), findsOneWidget);
    expect(find.text((4000).traffic.show), findsOneWidget);
    expect(find.text('RULE-SET'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('Node-A'), findsNothing);

    await tester.ensureVisible(find.text('Proxy').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proxy').last);
    await tester.pump();
    expect(find.text('Node-A'), findsOneWidget);

    await teardownWidget(tester);
  });

  testWidgets('page shows the empty state when nothing is recorded', (
    tester,
  ) async {
    container.dispose();
    container = createContainer(_data(count: 0));
    globalState.container = container;

    await pumpWidget(tester, const TrafficStatisticsView());

    expect(
      find.text(
        'No traffic recorded yet. Keep the tunnel on and come back after some connections close.',
      ),
      findsOneWidget,
    );
    expect(find.text('Overview'), findsNothing);

    await teardownWidget(tester);
  });
}
