import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart' as db;
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/traffic_statistics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import '../helpers/app_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.Database testDatabase;
  late ProviderContainer container;
  late Directory root;

  String hourName(DateTime at) =>
      '${at.year}-'
      '${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')}-'
      '${at.hour.toString().padLeft(2, '0')}';

  String line({
    required String id,
    String host = 'example.com',
    String process = 'Safari',
    String proxy = 'Proxy',
    String node = 'Node-A',
    bool direct = false,
    String rule = 'RULE-SET',
    String rulePayload = 'ads',
    int upload = 10,
    int download = 20,
    DateTime? start,
    DateTime? end,
  }) {
    final now = DateTime.now();
    return jsonEncode({
      'id': id,
      'host': host,
      'process': process,
      'proxy': proxy,
      'node': node,
      'direct': direct,
      'rule': rule,
      'rulePayload': rulePayload,
      'upload': upload,
      'download': download,
      'start': (start ?? now).millisecondsSinceEpoch,
      'end': (end ?? now).millisecondsSinceEpoch,
    });
  }

  Future<File> journalFile(DateTime at, String contents) async {
    final dir = Directory(path.join(root.path, 'traffic'));
    await dir.create(recursive: true);
    final file = File(path.join(dir.path, '${hourName(at)}.jsonl'));
    await file.writeAsString(contents);
    return file;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp();
    await useAppPaths(root);
    testDatabase = db.Database(NativeDatabase.memory());
    db.database = testDatabase;
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await testDatabase.close();
    await root.delete(recursive: true);
  });

  Future<List<db.TrafficStatisticsRecord>> rows() async {
    return (testDatabase.select(testDatabase.trafficStatistics)).get();
  }

  Future<List<db.TunnelSessionRecord>> sessions() async {
    return (testDatabase.select(testDatabase.tunnelSessions)).get();
  }

  test('journal rows are imported with their fields', () async {
    await journalFile(
      DateTime.now(),
      '${line(id: 'a')}\n'
      '${line(id: 'b', upload: 30, download: 40)}\n',
    );
    final recorder = container.read(trafficStatisticsRecorderProvider.notifier);
    await recorder.importJournal();

    final recorded = await rows();
    expect(recorded.map((row) => row.connectionId), ['a', 'b']);
    expect(recorded.first.upload, 10);
    expect(recorded.first.download, 20);
    expect(recorded.first.host, 'example.com');
    expect(recorded.first.process, 'Safari');
    expect(recorded.first.proxy, 'Proxy');
    expect(recorded.first.node, 'Node-A');
    expect(recorded.first.direct, isFalse);
    expect(recorded.first.rule, 'RULE-SET');
    expect(recorded.first.rulePayload, 'ads');
    expect(recorded.first.profileId, 0);
  });

  test('a second import skips rows already in the database', () async {
    await journalFile(
      DateTime.now(),
      '${line(id: 'a')}\n'
      '${line(id: 'b', upload: 30, download: 40)}\n',
    );
    final recorder = container.read(trafficStatisticsRecorderProvider.notifier);
    await recorder.importJournal();
    expect(await rows(), hasLength(2));

    final second = ProviderContainer();
    final secondRecorder = second.read(
      trafficStatisticsRecorderProvider.notifier,
    );
    await secondRecorder.importJournal();

    expect(await rows(), hasLength(2));
    second.dispose();
  });

  test('a direct journal line is recorded as direct', () async {
    await journalFile(
      DateTime.now(),
      '${line(id: 'a', host: '203.0.113.9', process: '', proxy: 'DIRECT', node: 'DIRECT', direct: true, rule: 'DIRECT', rulePayload: '', upload: 10, download: 40)}\n',
    );
    final recorder = container.read(trafficStatisticsRecorderProvider.notifier);
    await recorder.importJournal();

    final recorded = await rows();
    expect(recorded.single.direct, isTrue);
    expect(recorded.single.proxy, 'DIRECT');
    expect(recorded.single.node, 'DIRECT');
  });

  test('a malformed line never blocks the rest', () async {
    await journalFile(
      DateTime.now(),
      '${line(id: 'a')}\n'
      'not json\n'
      '${line(id: 'b', upload: 30, download: 40)}\n',
    );
    final recorder = container.read(trafficStatisticsRecorderProvider.notifier);
    await recorder.importJournal();

    expect((await rows()).map((row) => row.connectionId), ['a', 'b']);
  });

  test('a partial trailing line waits for the next import', () async {
    final now = DateTime.now();
    final file = await journalFile(now, '');
    final complete = line(id: 'a');
    final partial = line(id: 'b', upload: 30, download: 40);
    await file.writeAsString('$complete\n${partial.substring(0, 40)}');
    final recorder = container.read(trafficStatisticsRecorderProvider.notifier);
    await recorder.importJournal();
    expect((await rows()).map((row) => row.connectionId), ['a']);
    expect(await file.exists(), isTrue);

    await file.writeAsString(
      '${partial.substring(40)}\n',
      mode: FileMode.append,
    );
    final second = ProviderContainer();
    final secondRecorder = second.read(
      trafficStatisticsRecorderProvider.notifier,
    );
    await secondRecorder.importJournal();

    expect((await rows()).map((row) => row.connectionId), ['a', 'b']);
    second.dispose();
  });

  test(
    'a past-hour file is deleted after import, the current-hour file is kept',
    () async {
      final now = DateTime.now();
      final past = await journalFile(
        now.subtract(const Duration(hours: 2)),
        '${line(id: 'a')}\n',
      );
      final current = await journalFile(
        now,
        '${line(id: 'b', upload: 30, download: 40)}\n',
      );
      final recorder = container.read(
        trafficStatisticsRecorderProvider.notifier,
      );
      await recorder.importJournal();

      expect((await rows()).map((row) => row.connectionId), ['a', 'b']);
      expect(await past.exists(), isFalse);
      expect(await current.exists(), isTrue);
    },
  );

  test('the statistics provider totals the day and fills the trend', () async {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    await testDatabase.trafficStatisticsDao.recordClosed([
      db.TrafficStatisticsCompanion.insert(
        connectionId: 'a',
        host: 'example.com',
        process: 'Safari',
        proxy: 'Node-A',
        node: const Value('HK-01'),
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
        node: const Value('DIRECT'),
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
      trafficStatisticsProvider(TrafficStatisticsRange.day, 0).future,
    );

    expect(data.count, 2);
    expect(data.upload, 110);
    expect(data.download, 940);
    expect(data.total, 1050);
    expect(data.directUpload, 10);
    expect(data.directDownload, 40);
    expect(data.proxyUpload, 100);
    expect(data.uptime, Duration.zero);
    expect(data.start, dayStart);
    expect(data.trend.length, 24);
    expect(
      data.trend.fold<int>(0, (sum, bucket) => sum + bucket.download),
      940,
    );
    expect(data.ruleHits.map((hit) => (hit.label, hit.hits)), [
      ('ads', 1),
      ('DIRECT', 1),
    ]);
    expect(data.ruleHits.first.ruleType, 'RULE-SET');
    expect(data.domains.first.label, 'example.com');
    expect(data.domains.first.bytes, 1000);
    expect(data.domains.first.upload, 100);
    expect(data.domains.first.download, 900);
    expect(data.policies.single.label, 'Node-A');
    expect(data.nodes.single.label, 'HK-01');
    expect(data.nodes.single.bytes, 1000);
    expect(data.profiles.single.label, 'Home');
  });

  test('the statistics provider reads an earlier day with an offset', () async {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    await testDatabase.trafficStatisticsDao.recordClosed([
      db.TrafficStatisticsCompanion.insert(
        connectionId: 'old',
        host: 'example.com',
        process: '',
        proxy: 'Node-A',
        direct: false,
        rule: 'DIRECT',
        rulePayload: '',
        upload: 10,
        download: 40,
        startedAt: yesterday.add(const Duration(hours: 10)),
        endedAt: yesterday.add(const Duration(hours: 10, minutes: 1)),
        profileId: 1,
        profileLabel: 'Home',
      ),
    ]);

    final today = await container.read(
      trafficStatisticsProvider(TrafficStatisticsRange.day, 0).future,
    );
    expect(today.count, 0);

    final past = await container.read(
      trafficStatisticsProvider(TrafficStatisticsRange.day, 1).future,
    );
    expect(past.count, 1);
    expect(past.start, yesterday);
    expect(past.end, yesterday.add(const Duration(days: 1)));
  });

  test('a tunnel session opens on start and closes on stop', () async {
    final recorder = container.read(trafficStatisticsRecorderProvider.notifier);
    await recorder.noteTunnelRunning(true);

    var found = await sessions();
    expect(found, hasLength(1));
    expect(found.single.endedAt, isNull);

    await recorder.noteTunnelRunning(false);

    found = await sessions();
    expect(found, hasLength(1));
    expect(found.single.endedAt, isNotNull);

    final data = await container.read(
      trafficStatisticsProvider(TrafficStatisticsRange.day, 0).future,
    );
    expect(data.uptime, greaterThanOrEqualTo(Duration.zero));
  });

  test('the statistics provider fills the whole week', () async {
    final data = await container.read(
      trafficStatisticsProvider(TrafficStatisticsRange.week, 0).future,
    );

    expect(data.count, 0);
    expect(data.trend.length, 7);
    expect(data.trend.every((bucket) => bucket.download == 0), isTrue);
  });

  test(
    'clearing removes every record and session and empties the page',
    () async {
      final file = await journalFile(DateTime.now(), '${line(id: 'a')}\n');
      final recorder = container.read(
        trafficStatisticsRecorderProvider.notifier,
      );
      await recorder.importJournal();
      expect(await rows(), hasLength(1));

      await recorder.clear();

      expect(await rows(), isEmpty);
      expect(await sessions(), isEmpty);
      expect(await file.exists(), isFalse);
      final data = await container.read(
        trafficStatisticsProvider(TrafficStatisticsRange.day, 0).future,
      );
      expect(data.count, 0);
      expect(data.total, 0);
      expect(data.uptime, Duration.zero);
    },
  );

  test('clearing while the tunnel is up reopens a session and deletes '
      'journal files', () async {
    final file = await journalFile(DateTime.now(), '${line(id: 'a')}\n');
    container.read(runTimeProvider.notifier).value = 1000;
    final recorder = container.read(trafficStatisticsRecorderProvider.notifier);
    await recorder.importJournal();
    expect(await rows(), hasLength(1));

    await recorder.clear();

    expect(await rows(), isEmpty);
    expect(await file.exists(), isFalse);
    final found = await sessions();
    expect(found, hasLength(1));
    expect(found.single.endedAt, isNull);

    final data = await container.read(
      trafficStatisticsProvider(TrafficStatisticsRange.day, 0).future,
    );
    expect(data.count, 0);
    expect(data.uptime, lessThanOrEqualTo(const Duration(seconds: 1)));
  });

  test('the statistics provider returns empty data without rows', () async {
    final now = DateTime.now();
    final data = await container.read(
      trafficStatisticsProvider(TrafficStatisticsRange.month, 0).future,
    );

    expect(data.count, 0);
    expect(data.total, 0);
    expect(data.uptime, Duration.zero);
    expect(data.ruleHits, isEmpty);
    expect(data.domains, isEmpty);
    expect(data.trend.length, DateTime(now.year, now.month + 1, 0).day);
    expect(data.trend.every((bucket) => bucket.download == 0), isTrue);
  });
}
