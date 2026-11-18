import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart' as db;
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/traffic_statistics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.Database testDatabase;
  late ProviderContainer container;
  late TrafficStatisticsRecorder recorder;

  TrackerInfo connection({
    required String id,
    String host = 'example.com',
    String process = 'Safari',
    List<String> chains = const ['Proxy', 'Node-A'],
    String rule = 'RULE-SET',
    String rulePayload = 'ads',
    int upload = 0,
    int download = 0,
    DateTime? start,
  }) {
    return TrackerInfo(
      id: id,
      upload: upload,
      download: download,
      start: start ?? DateTime(2026, 11, 19, 10, 0),
      metadata: Metadata(host: host, process: process),
      chains: chains,
      rule: rule,
      rulePayload: rulePayload,
    );
  }

  setUp(() {
    testDatabase = db.Database(NativeDatabase.memory());
    db.database = testDatabase;
    container = ProviderContainer();
    container.read(runTimeProvider.notifier).value = 1000;
    recorder = container.read(trafficStatisticsRecorderProvider.notifier);
  });

  tearDown(() async {
    container.dispose();
    await testDatabase.close();
  });

  Future<List<db.TrafficStatisticsRecord>> rows() async {
    return (testDatabase.select(testDatabase.trafficStatistics)).get();
  }

  test('a connection is recorded once it leaves the live list', () async {
    recorder.onRequest(connection(id: 'a', upload: 10, download: 20));
    recorder.onRequest(connection(id: 'b', upload: 30, download: 40));
    recorder.onRequestTraffic({'a': (upload: 100, download: 900)});

    await recorder.onLiveConnections([
      connection(id: 'a', upload: 100, download: 900),
    ]);

    final recorded = await rows();
    expect(recorded.map((row) => row.connectionId), ['b']);
    expect(recorded.single.upload, 30);
    expect(recorded.single.download, 40);
    expect(recorded.single.host, 'example.com');
    expect(recorded.single.process, 'Safari');
    expect(recorded.single.proxy, 'Node-A');
    expect(recorded.single.direct, isFalse);
    expect(recorded.single.rule, 'RULE-SET');
    expect(recorded.single.rulePayload, 'ads');

    await recorder.onLiveConnections([]);

    final all = await rows();
    expect(all.map((row) => row.connectionId), ['b', 'a']);
    expect(all.last.upload, 100);
    expect(all.last.download, 900);
  });

  test(
    'a connection missing from the events is picked up from the snapshot',
    () async {
      await recorder.onLiveConnections([
        connection(id: 'a', upload: 5, download: 15),
      ]);
      await recorder.onLiveConnections([]);

      final recorded = await rows();
      expect(recorded.single.connectionId, 'a');
      expect(recorded.single.upload, 5);
      expect(recorded.single.download, 15);
    },
  );

  test('a direct connection is recorded as direct', () async {
    recorder.onRequest(
      connection(
        id: 'a',
        host: '203.0.113.9',
        process: '',
        chains: const ['DIRECT'],
        rule: 'DIRECT',
        rulePayload: '',
        upload: 10,
        download: 40,
      ),
    );

    await recorder.onLiveConnections([]);

    final recorded = await rows();
    expect(recorded.single.direct, isTrue);
    expect(recorded.single.proxy, 'DIRECT');
  });

  test('stopping the tunnel flushes the open connections', () async {
    recorder.onRequest(connection(id: 'a', upload: 7, download: 8));

    container.read(runTimeProvider.notifier).value = null;
    recorder.onRequest(connection(id: 'b'));

    await recorder.flush();

    final recorded = await rows();
    expect(recorded.map((row) => row.connectionId), ['a']);
    expect(recorded.single.upload, 7);
  });

  test('the statistics provider totals the day and fills the trend', () async {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    await testDatabase.trafficStatisticsDao.recordClosed([
      db.TrafficStatisticsCompanion.insert(
        connectionId: 'a',
        host: 'example.com',
        process: 'Safari',
        proxy: 'Node-A',
        direct: false,
        rule: 'RULE-SET',
        rulePayload: 'ads',
        upload: 100,
        download: 900,
        startedAt: now.subtract(const Duration(minutes: 5)),
        endedAt: now.subtract(const Duration(minutes: 1)),
        profileId: 1,
        profileLabel: 'Home',
      ),
      db.TrafficStatisticsCompanion.insert(
        connectionId: 'b',
        host: '203.0.113.9',
        process: '',
        proxy: 'DIRECT',
        direct: true,
        rule: 'DIRECT',
        rulePayload: '',
        upload: 10,
        download: 40,
        startedAt: now.subtract(const Duration(minutes: 4)),
        endedAt: now.subtract(const Duration(minutes: 1)),
        profileId: 1,
        profileLabel: 'Home',
      ),
    ]);

    final data = await container.read(
      trafficStatisticsProvider(TrafficStatisticsRange.day).future,
    );

    expect(data.count, 2);
    expect(data.upload, 110);
    expect(data.download, 940);
    expect(data.total, 1050);
    expect(data.directUpload, 10);
    expect(data.directDownload, 40);
    expect(data.proxyUpload, 100);
    expect(data.start, dayStart);
    expect(data.trend.length, now.hour + 1);
    expect(
      data.trend.fold<int>(0, (sum, bucket) => sum + bucket.download),
      940,
    );
    expect(data.ruleHits.map((hit) => (hit.label, hit.hits)), [
      ('ads', 1),
      ('DIRECT', 1),
    ]);
    expect(data.domains.first.label, 'example.com');
    expect(data.domains.first.bytes, 1000);
    expect(data.proxies.single.label, 'Node-A');
    expect(data.profiles.single.label, 'Home');
  });

  test('the statistics provider returns empty data without rows', () async {
    final now = DateTime.now();
    final data = await container.read(
      trafficStatisticsProvider(TrafficStatisticsRange.month).future,
    );

    expect(data.count, 0);
    expect(data.total, 0);
    expect(data.ruleHits, isEmpty);
    expect(data.domains, isEmpty);
    expect(data.trend.length, now.day);
    expect(data.trend.every((bucket) => bucket.download == 0), isTrue);
  });
}
