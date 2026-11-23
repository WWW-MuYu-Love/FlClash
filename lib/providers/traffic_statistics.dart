import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:path/path.dart' as path;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'generated/traffic_statistics.g.dart';

enum TrafficStatisticsRange { day, week, month }

class TrafficStatisticsData {
  const TrafficStatisticsData({
    required this.range,
    required this.start,
    required this.end,
    required this.count,
    required this.upload,
    required this.download,
    required this.directUpload,
    required this.directDownload,
    required this.uptime,
    required this.trend,
    required this.ruleHits,
    required this.domains,
    required this.policies,
    required this.nodes,
    required this.profiles,
  });

  final TrafficStatisticsRange range;
  final DateTime start;
  final DateTime end;
  final int count;
  final int upload;
  final int download;
  final int directUpload;
  final int directDownload;
  final Duration uptime;
  final List<TrafficStatisticsBucket> trend;
  final List<TrafficStatisticsRank> ruleHits;
  final List<TrafficStatisticsRank> domains;
  final List<TrafficStatisticsRank> policies;
  final List<TrafficStatisticsRank> nodes;
  final List<TrafficStatisticsRank> profiles;

  int get total => upload + download;

  int get proxyUpload => upload - directUpload;

  int get proxyDownload => download - directDownload;

  int get totalRuleHits => ruleHits.fold<int>(0, (sum, hit) => sum + hit.hits);
}

int maxTrafficStatisticsOffset(TrafficStatisticsRange range) {
  return switch (range) {
    TrafficStatisticsRange.day => 89,
    TrafficStatisticsRange.week => 12,
    TrafficStatisticsRange.month => 2,
  };
}

String trafficStatisticsRangeLabel(TrafficStatisticsRange range, int offset) {
  final now = DateTime.now();
  final (start, end, _) = _rangeWindow(range, now, offset);
  switch (range) {
    case TrafficStatisticsRange.day:
      return _dateLabel(start);
    case TrafficStatisticsRange.week:
      final last = offset == 0 ? now : end.subtract(const Duration(days: 1));
      return '${_shortDateLabel(start)} ~ ${_shortDateLabel(last)}';
    case TrafficStatisticsRange.month:
      return '${start.year}-${_twoDigits(start.month)}';
  }
}

String _dateLabel(DateTime date) =>
    '${date.year}-${_twoDigits(date.month)}-${_twoDigits(date.day)}';

String _shortDateLabel(DateTime date) =>
    '${_twoDigits(date.month)}-${_twoDigits(date.day)}';

String _twoDigits(int value) => value.toString().padLeft(2, '0');

@Riverpod(keepAlive: true)
class TrafficStatisticsRecorder extends _$TrafficStatisticsRecorder {
  DateTime? _lastPruneAt;
  DateTime? _lastInvalidatedAt;
  DateTime? _lastImportAt;
  Future<void> _writes = Future.value();
  Future<void>? _importing;
  int? _openSessionId;
  final _importOffsets = <String, int>{};

  @override
  void build() {
    unawaited(importJournal());
  }

  bool get _tunnelUp => ref.read(isStartProvider);

  /// Opens a tunnel session when the tunnel starts and closes it when it
  /// stops. Called directly from the setup action: a listener on the
  /// tunnel state cannot do this, Riverpod pauses it while nothing
  /// watches this provider.
  Future<void> noteTunnelRunning(bool running) {
    return running ? _openSession() : _closeSession();
  }

  Future<void> _openSession() {
    final run = _writes.then((_) async {
      if (_openSessionId != null) {
        return;
      }
      final now = DateTime.now();
      try {
        await database.tunnelSessionsDao.closeOpenSessions(now);
        _openSessionId = await database.tunnelSessionsDao.openSession(now);
      } catch (error) {
        commonPrint.log(
          'Traffic statistics session failed: ${compactError(error)}',
          logLevel: LogLevel.warning,
        );
      }
    });
    _writes = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _closeSession() {
    final run = _writes.then((_) async {
      try {
        await database.tunnelSessionsDao.closeOpenSessions(DateTime.now());
      } catch (error) {
        commonPrint.log(
          'Traffic statistics session failed: ${compactError(error)}',
          logLevel: LogLevel.warning,
        );
      }
      _openSessionId = null;
    });
    _writes = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<void> importJournal() {
    final running = _importing;
    if (running != null) {
      return running;
    }
    final now = DateTime.now();
    final lastImportAt = _lastImportAt;
    if (lastImportAt != null &&
        now.difference(lastImportAt) < const Duration(seconds: 10)) {
      return Future.value();
    }
    _lastImportAt = now;
    final run = _writes.then((_) => _importJournal(now));
    _importing = run;
    _writes = run.then<void>((_) {}, onError: (_) {});
    unawaited(
      run.whenComplete(() {
        if (identical(_importing, run)) {
          _importing = null;
        }
      }),
    );
    return run;
  }

  Future<void> _importJournal(DateTime now) async {
    final profile = _profile();
    var imported = 0;
    try {
      for (final dir in await _journalDirs()) {
        imported += await _importDir(dir, profile, now);
      }
    } catch (error) {
      commonPrint.log(
        'Traffic statistics import failed: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      return;
    }
    await _pruneIfDue(now);
    if (imported > 0) {
      _invalidateStatistics(now);
    }
  }

  Future<List<Directory>> _journalDirs() async {
    if (system.isIOS) {
      // The app core's own journal stays out: it holds probes and
      // system-proxy traffic the page never counted.
      final shared = await appPath.sharedIOSFlClashDirPath;
      if (shared == null) {
        return const [];
      }
      return [Directory(path.join(shared, trafficJournalDirectoryName))];
    }
    return [
      Directory(
        path.join(await appPath.homeDirPath, trafficJournalDirectoryName),
      ),
    ];
  }

  // The journal files are small, so the importer reads them synchronously:
  // async file reads in a background import can stall behind the event loop.
  Future<int> _importDir(
    Directory dir,
    (int, String) profile,
    DateTime now,
  ) async {
    if (!dir.existsSync()) {
      return 0;
    }
    final currentHour = DateTime(now.year, now.month, now.day, now.hour);
    final files = [
      for (final entity in dir.listSync())
        if (entity is File && entity.path.endsWith(trafficJournalFileSuffix))
          entity,
    ];
    files.sort((a, b) => a.path.compareTo(b.path));
    var imported = 0;
    for (final file in files) {
      try {
        imported += await _importFile(file, profile, currentHour);
      } catch (error) {
        commonPrint.log(
          'Traffic statistics import failed: ${compactError(error)}',
          logLevel: LogLevel.warning,
        );
      }
    }
    return imported;
  }

  Future<int> _importFile(
    File file,
    (int, String) profile,
    DateTime currentHour,
  ) async {
    final hour = _journalFileHour(path.basename(file.path));
    if (hour == null) {
      return 0;
    }
    final bytes = file.readAsBytesSync();
    var offset = _importOffsets[file.path] ?? 0;
    if (offset > bytes.length) {
      offset = 0;
    }
    final fresh = utf8.decode(bytes.sublist(offset));
    final lastNewline = fresh.lastIndexOf('\n');
    if (lastNewline < 0) {
      if (hour.isBefore(currentHour)) {
        file.deleteSync();
        _importOffsets.remove(file.path);
      }
      return 0;
    }
    final consumed = fresh.substring(0, lastNewline + 1);
    final rows = <TrafficStatisticsCompanion>[];
    final lines = consumed.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final row = _journalRow(lines[i], profile);
      if (row != null) {
        rows.add(row);
      }
      if (i % 256 == 255) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    var imported = 0;
    if (rows.isNotEmpty) {
      final ids = {for (final row in rows) row.connectionId.value};
      final existing = await database.trafficStatisticsDao.existingIds(ids);
      final freshRows = [
        for (final row in rows)
          if (!existing.contains(row.connectionId.value)) row,
      ];
      if (freshRows.isNotEmpty) {
        await database.trafficStatisticsDao.recordClosed(freshRows);
        imported = freshRows.length;
      }
    }
    _importOffsets[file.path] = offset + utf8.encode(consumed).length;
    if (hour.isBefore(currentHour)) {
      file.deleteSync();
      _importOffsets.remove(file.path);
    }
    return imported;
  }

  DateTime? _journalFileHour(String name) {
    final stem = name.endsWith(trafficJournalFileSuffix)
        ? name.substring(0, name.length - trafficJournalFileSuffix.length)
        : name;
    final parts = stem.split('-');
    if (parts.length != 4) {
      return null;
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    final hour = int.tryParse(parts[3]);
    if (year == null || month == null || day == null || hour == null) {
      return null;
    }
    return DateTime(year, month, day, hour);
  }

  TrafficStatisticsCompanion? _journalRow(String line, (int, String) profile) {
    if (line.isEmpty) {
      return null;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final id = decoded['id'];
    final host = decoded['host'];
    final process = decoded['process'];
    final proxy = decoded['proxy'];
    final node = decoded['node'];
    final direct = decoded['direct'];
    final rule = decoded['rule'];
    final rulePayload = decoded['rulePayload'];
    final upload = decoded['upload'];
    final download = decoded['download'];
    final start = decoded['start'];
    final end = decoded['end'];
    if (id is! String ||
        id.isEmpty ||
        host is! String ||
        process is! String ||
        proxy is! String ||
        node is! String ||
        direct is! bool ||
        rule is! String ||
        rulePayload is! String ||
        upload is! int ||
        download is! int ||
        start is! int ||
        end is! int) {
      return null;
    }
    return TrafficStatisticsCompanion.insert(
      connectionId: id,
      host: host,
      process: process,
      proxy: proxy,
      node: Value(node.isEmpty ? null : node),
      direct: direct,
      rule: rule,
      rulePayload: rulePayload,
      upload: upload,
      download: download,
      startedAt: DateTime.fromMillisecondsSinceEpoch(start),
      endedAt: DateTime.fromMillisecondsSinceEpoch(end),
      profileId: profile.$1,
      profileLabel: profile.$2,
    );
  }

  Future<void> _deleteJournalFiles() async {
    for (final dir in await _journalDirs()) {
      if (!dir.existsSync()) {
        continue;
      }
      for (final entity in dir.listSync()) {
        if (entity is File && entity.path.endsWith(trafficJournalFileSuffix)) {
          entity.deleteSync();
        }
      }
    }
  }

  (int, String) _profile() {
    final profile = ref.read(currentProfileProvider);
    return (profile?.id ?? 0, profile?.realLabel ?? '');
  }

  /// Reopens a live session after the wipe, or uptime stalls on a deleted row.
  Future<void> clear() {
    final run = _writes.then((_) async {
      _openSessionId = null;
      _importOffsets.clear();
      try {
        await database.trafficStatisticsDao.clear();
        await database.tunnelSessionsDao.clear();
        if (_tunnelUp) {
          _openSessionId = await database.tunnelSessionsDao.openSession(
            DateTime.now(),
          );
        }
      } catch (error) {
        commonPrint.log(
          'Traffic statistics clear failed: ${compactError(error)}',
          logLevel: LogLevel.warning,
        );
      }
      try {
        await _deleteJournalFiles();
      } catch (error) {
        commonPrint.log(
          'Traffic statistics journal clear failed: ${compactError(error)}',
          logLevel: LogLevel.warning,
        );
      }
      ref.invalidate(trafficStatisticsProvider);
    });
    _writes = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _pruneIfDue(DateTime now) async {
    final lastPruneAt = _lastPruneAt;
    if (lastPruneAt != null &&
        now.difference(lastPruneAt) < const Duration(hours: 1)) {
      return;
    }
    _lastPruneAt = now;
    await _prune();
  }

  Future<void> _prune() async {
    try {
      await database.trafficStatisticsDao.pruneOlderThan(
        DateTime.now().subtract(trafficStatisticsRetention),
      );
    } catch (error) {
      commonPrint.log(
        'Traffic statistics prune failed: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
    }
  }

  void _invalidateStatistics(DateTime now) {
    final lastInvalidatedAt = _lastInvalidatedAt;
    if (lastInvalidatedAt != null &&
        now.difference(lastInvalidatedAt) < const Duration(seconds: 10)) {
      return;
    }
    _lastInvalidatedAt = now;
    ref.invalidate(trafficStatisticsProvider);
  }
}

@riverpod
Future<TrafficStatisticsData> trafficStatistics(
  Ref ref,
  TrafficStatisticsRange range,
  int offset,
) async {
  final dao = database.trafficStatisticsDao;
  final sessionsDao = database.tunnelSessionsDao;
  final now = DateTime.now();
  final (start, end, hourly) = _rangeWindow(range, now, offset);
  await dao.pruneOlderThan(now.subtract(trafficStatisticsRetention));
  await sessionsDao.pruneClosedBefore(now.subtract(trafficStatisticsRetention));
  final results = await Future.wait([
    dao.totals(start, end),
    dao.trend(start, end, hourly: hourly),
    dao.ruleHits(start, end),
    dao.rankBy(TrafficStatisticsRankBy.domain, start, end),
    dao.rankBy(TrafficStatisticsRankBy.policy, start, end),
    dao.rankBy(TrafficStatisticsRankBy.node, start, end),
    dao.rankBy(TrafficStatisticsRankBy.profile, start, end),
    sessionsDao.uptime(start, end),
  ]);
  final totals = results[0] as TrafficStatisticsTotals;
  final buckets = results[1] as List<TrafficStatisticsBucket>;
  return TrafficStatisticsData(
    range: range,
    start: start,
    end: end,
    count: totals.count,
    upload: totals.upload,
    download: totals.download,
    directUpload: totals.directUpload,
    directDownload: totals.directDownload,
    uptime: results[7] as Duration,
    trend: _fillTrend(range, start, hourly, buckets),
    ruleHits: results[2] as List<TrafficStatisticsRank>,
    domains: results[3] as List<TrafficStatisticsRank>,
    policies: results[4] as List<TrafficStatisticsRank>,
    nodes: results[5] as List<TrafficStatisticsRank>,
    profiles: results[6] as List<TrafficStatisticsRank>,
  );
}

(DateTime, DateTime, bool) _rangeWindow(
  TrafficStatisticsRange range,
  DateTime now,
  int offset,
) {
  final dayStart = DateTime(now.year, now.month, now.day);
  switch (range) {
    case TrafficStatisticsRange.day:
      final start = dayStart.subtract(Duration(days: offset));
      return (
        start,
        offset == 0 ? now : start.add(const Duration(days: 1)),
        true,
      );
    case TrafficStatisticsRange.week:
      final start = dayStart.subtract(
        Duration(days: now.weekday - 1 + offset * 7),
      );
      return (
        start,
        offset == 0 ? now : start.add(const Duration(days: 7)),
        false,
      );
    case TrafficStatisticsRange.month:
      final start = DateTime(now.year, now.month - offset);
      return (
        start,
        offset == 0 ? now : DateTime(start.year, start.month + 1),
        false,
      );
  }
}

List<TrafficStatisticsBucket> _fillTrend(
  TrafficStatisticsRange range,
  DateTime start,
  bool hourly,
  List<TrafficStatisticsBucket> buckets,
) {
  final byStart = {for (final bucket in buckets) bucket.start: bucket};
  final trend = <TrafficStatisticsBucket>[];
  var cursor = DateTime(start.year, start.month, start.day);
  final DateTime last;
  if (hourly) {
    last = DateTime(start.year, start.month, start.day, 23);
  } else if (range == TrafficStatisticsRange.week) {
    last = start.add(const Duration(days: 6));
  } else {
    last = DateTime(
      start.year,
      start.month + 1,
    ).subtract(const Duration(days: 1));
  }
  while (!cursor.isAfter(last)) {
    trend.add(
      byStart[cursor] ??
          TrafficStatisticsBucket(start: cursor, upload: 0, download: 0),
    );
    cursor = hourly
        ? cursor.add(const Duration(hours: 1))
        : cursor.add(const Duration(days: 1));
  }
  return trend;
}
