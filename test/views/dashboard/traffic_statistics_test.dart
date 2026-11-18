import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/traffic_statistics.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/views/dashboard/widgets/traffic_statistics.dart';
import 'package:fl_clash/views/traffic_statistics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../helpers/host_scaffold.dart';
import '../../helpers/test_app.dart';

const _size = Size(400, 800);

TrafficStatisticsData _data({
  int count = 3,
  TrafficStatisticsRange range = TrafficStatisticsRange.day,
  List<TrafficStatisticsBucket>? trend,
  List<TrafficStatisticsRank>? ruleHits,
}) {
  final start = DateTime(2026, 11, 19);
  return TrafficStatisticsData(
    range: range,
    start: start,
    end: start.add(const Duration(hours: 10)),
    count: count,
    upload: 1500,
    download: 2500,
    directUpload: 500,
    directDownload: 500,
    uptime: const Duration(hours: 17, minutes: 26),
    trend:
        trend ??
        [
          TrafficStatisticsBucket(start: start, upload: 100, download: 200),
          TrafficStatisticsBucket(
            start: start.add(const Duration(hours: 1)),
            upload: 1400,
            download: 2300,
          ),
        ],
    ruleHits:
        ruleHits ??
        const [
          TrafficStatisticsRank(label: 'RULE-SET', bytes: 3000, hits: 2),
          TrafficStatisticsRank(label: 'DIRECT', bytes: 1000, hits: 1),
        ],
    domains: const [
      TrafficStatisticsRank(label: 'example.com', bytes: 3000, hits: 2),
      TrafficStatisticsRank(label: 'other.test', bytes: 1000, hits: 1),
    ],
    proxies: const [
      TrafficStatisticsRank(label: 'Node-A', bytes: 3000, hits: 2),
    ],
    profiles: const [
      TrafficStatisticsRank(label: 'Default', bytes: 4000, hits: 3),
    ],
    rules: const [TrafficStatisticsRank(label: 'ads', bytes: 1000, hits: 1)],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  ProviderContainer createContainer(TrafficStatisticsData data) {
    return ProviderContainer(
      overrides: [
        for (final range in TrafficStatisticsRange.values)
          trafficStatisticsProvider(range, 0).overrideWith((_) async => data),
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
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('Proxy'), findsOneWidget);
    expect(find.text('Direct'), findsOneWidget);
    expect(find.text('Uptime 17 hours 26 minutes'), findsOneWidget);

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
    expect(find.text('Traffic summary'), findsOneWidget);
    expect(find.text('Trend'), findsOneWidget);
    expect(find.text('Rule hits'), findsOneWidget);
    expect(find.text('Rankings'), findsOneWidget);
    expect(find.textContaining('3.9 KB', findRichText: true), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    expect(
      find.text('17 hours 26 minutes', findRichText: true),
      findsOneWidget,
    );
    final now = DateTime.now();
    expect(
      find.text(
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}',
      ),
      findsOneWidget,
    );
    expect(find.text('RULE-SET'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('Node-A'), findsNothing);
    expect(find.text('ads'), findsNothing);

    await tester.ensureVisible(find.text('Nodes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nodes'));
    await tester.pump();
    expect(find.text('Node-A'), findsOneWidget);

    await tester.ensureVisible(find.text('Rule').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rule').last);
    await tester.pump();
    expect(find.text('ads'), findsOneWidget);

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(find.textContaining('3.9 KB', findRichText: true), findsOneWidget);

    await teardownWidget(tester);
  });

  testWidgets('overview splits proxy and direct into separate cells', (
    tester,
  ) async {
    await pumpWidget(tester, const TrafficStatisticsView());

    final uptimeLabel = tester.widget<Text>(find.text('Uptime'));
    final BuildContext uptimeContext = tester.element(find.text('Uptime'));
    expect(uptimeLabel.style?.fontWeight, isNot(FontWeight.w600));
    expect(
      uptimeLabel.style?.color,
      uptimeContext.colorScheme.onSurfaceVariant,
    );

    Container splitCell(Finder label) {
      return tester.widget<Container>(
        find.ancestor(of: label, matching: find.byType(Container)).first,
      );
    }

    final proxyCell = splitCell(find.text('Proxy').last);
    final directCell = splitCell(find.text('Direct'));
    expect(identical(proxyCell, directCell), isFalse);

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

  test('trend bars stay thin in wide slots and scale with narrow ones', () {
    expect(trafficTrendBarWidth(42.0), 16.0);
    expect(trafficTrendBarWidth(30.0), 16.0);
    expect(trafficTrendBarWidth(10.0), 6.0);
    expect(trafficTrendBarWidth(8.0), moreOrLessEquals(4.8));
  });

  test('trend grid fractions cover every range end to end', () {
    expect(trafficTrendGridFractions(TrafficStatisticsRange.day, 24), [
      0.0,
      0.25,
      0.5,
      0.75,
      1.0,
    ]);
    final week = trafficTrendGridFractions(TrafficStatisticsRange.week, 7);
    expect(week, hasLength(8));
    expect(week.first, 0.0);
    expect(week.last, 1.0);
    expect(week[3], moreOrLessEquals(3 / 7));
    expect(trafficTrendGridFractions(TrafficStatisticsRange.month, 28), [
      0.0,
      0.25,
      0.5,
      0.75,
      1.0,
    ]);
    final month30 = trafficTrendGridFractions(TrafficStatisticsRange.month, 30);
    expect(month30, hasLength(6));
    expect(month30.first, 0.0);
    expect(month30.last, 1.0);
    expect(month30[1], moreOrLessEquals(7 / 30));
    expect(month30[4], moreOrLessEquals(28 / 30));
    expect(
      trafficTrendGridFractions(TrafficStatisticsRange.month, 31),
      hasLength(6),
    );
  });

  Finder findTrendGrid() {
    return find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.painter?.runtimeType.toString() == '_TrendGridPainter',
    );
  }

  testWidgets('trend grid mounts in the day view', (tester) async {
    await pumpWidget(tester, const TrafficStatisticsView());

    expect(findTrendGrid(), findsOneWidget);

    await teardownWidget(tester);
  });

  testWidgets('trend grid mounts in the week view', (tester) async {
    container.dispose();
    container = createContainer(
      _data(
        range: TrafficStatisticsRange.week,
        trend: [
          for (var i = 0; i < 7; i++)
            TrafficStatisticsBucket(
              start: DateTime(2026, 11, 16).add(Duration(days: i)),
              upload: 100,
              download: 200,
            ),
        ],
      ),
    );
    globalState.container = container;

    await pumpWidget(tester, const TrafficStatisticsView());
    await tester.tap(find.text('Week'));
    await tester.pump();
    await tester.pump();

    expect(findTrendGrid(), findsOneWidget);

    await teardownWidget(tester);
  });

  testWidgets('trend grid mounts in the month view', (tester) async {
    container.dispose();
    container = createContainer(
      _data(
        range: TrafficStatisticsRange.month,
        trend: [
          for (var i = 0; i < 30; i++)
            TrafficStatisticsBucket(
              start: DateTime(2026, 11, 1).add(Duration(days: i)),
              upload: 100,
              download: 200,
            ),
        ],
      ),
    );
    globalState.container = container;

    await pumpWidget(tester, const TrafficStatisticsView());
    await tester.tap(find.text('Month'));
    await tester.pump();
    await tester.pump();

    expect(findTrendGrid(), findsOneWidget);

    await teardownWidget(tester);
  });

  testWidgets('day trend hour labels stay on one line', (tester) async {
    await pumpWidget(tester, const TrafficStatisticsView());

    for (final hour in ['12', '18']) {
      final label = tester.widget<Text>(find.text(hour));
      expect(label.softWrap, isFalse);
      expect(label.textAlign, TextAlign.center);
    }

    await teardownWidget(tester);
  });

  testWidgets('week trend date labels stay on one line', (tester) async {
    container.dispose();
    container = createContainer(
      _data(
        range: TrafficStatisticsRange.week,
        trend: [
          for (var i = 0; i < 7; i++)
            TrafficStatisticsBucket(
              start: DateTime(2026, 11, 16).add(Duration(days: i)),
              upload: 100,
              download: 200,
            ),
        ],
      ),
    );
    globalState.container = container;

    await pumpWidget(tester, const TrafficStatisticsView());
    await tester.tap(find.text('Week'));
    await tester.pump();
    await tester.pump();

    for (final label in ['11-16', '11-19', '11-22']) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.softWrap, isFalse);
      expect(text.maxLines, 1);
    }

    await teardownWidget(tester);
  });

  testWidgets('rule hit cards tint type tags and show full counts', (
    tester,
  ) async {
    container.dispose();
    container = createContainer(
      _data(
        ruleHits: const [
          TrafficStatisticsRank(
            label: 'DIRECT',
            bytes: 10485760,
            hits: 1404,
            ruleType: 'Match',
          ),
          TrafficStatisticsRank(
            label: 'ads',
            bytes: 3000,
            hits: 2,
            ruleType: 'RuleSet',
          ),
        ],
      ),
    );
    globalState.container = container;

    await pumpWidget(tester, const TrafficStatisticsView());

    expect(find.text('1404 hits · ${(10485760).traffic.show}'), findsOneWidget);
    expect(find.text('1404 hits'), findsNothing);
    expect(find.text((10485760).traffic.show), findsNothing);
    for (final ruleType in ['Match', 'RuleSet']) {
      final tag = find.text(ruleType);
      expect(tag, findsOneWidget);
      final tagText = tester.widget<Text>(tag);
      final BuildContext tagContext = tester.element(tag);
      expect(tagText.style?.color, tagContext.colorScheme.onPrimaryContainer);
      final pill = tester.widget<Container>(
        find.ancestor(of: tag, matching: find.byType(Container)).first,
      );
      expect(
        (pill.decoration as ShapeDecoration?)?.color,
        tagContext.colorScheme.primaryContainer,
      );
    }

    await teardownWidget(tester);
  });

  testWidgets('rule hit cards tint other types with the warning color', (
    tester,
  ) async {
    container.dispose();
    container = createContainer(
      _data(
        ruleHits: const [
          TrafficStatisticsRank(
            label: 'geo',
            bytes: 100,
            hits: 1,
            ruleType: 'GeoIP',
          ),
        ],
      ),
    );
    globalState.container = container;

    await pumpWidget(tester, const TrafficStatisticsView());

    final otherTag = find.text('GeoIP');
    expect(otherTag, findsOneWidget);
    final otherText = tester.widget<Text>(otherTag);
    final BuildContext otherContext = tester.element(otherTag);
    final otherColors = DashboardColors.of(otherContext);
    expect(otherText.style?.color, otherColors.onWarnContainer);
    final otherPill = tester.widget<Container>(
      find.ancestor(of: otherTag, matching: find.byType(Container)).first,
    );
    expect(
      (otherPill.decoration as ShapeDecoration?)?.color,
      otherColors.warnContainer,
    );

    await teardownWidget(tester);
  });
}
