import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/state.dart';
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
    required this.proxies,
    required this.profiles,
    required this.rules,
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
  final List<TrafficStatisticsRank> proxies;
  final List<TrafficStatisticsRank> profiles;
  final List<TrafficStatisticsRank> rules;

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

/// Records closed connections while the tunnel is up: opens and traffic
/// updates arrive as core events, and the live snapshot says which ones
/// have closed. A connection the event queue dropped still shows up in the
/// snapshot and is picked up from there.
@Riverpod(keepAlive: true)
class TrafficStatisticsRecorder extends _$TrafficStatisticsRecorder {
  final _open = <String, _OpenConnection>{};
  DateTime? _lastPruneAt;
  DateTime? _lastInvalidatedAt;
  Future<void> _writes = Future.value();
  int? _openSessionId;

  @override
  void build() {
    // Pruning waits for the first live snapshot: the database may not be
    // openable yet when this notifier is first read.
    ref.listen(isStartProvider, (_, running) {
      if (running) {
        unawaited(_openSession());
      } else {
        unawaited(_closeSession());
      }
    });
  }

  bool get _tunnelUp => ref.read(isStartProvider);

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

  void _ensureSessionOpen() {
    if (_openSessionId != null) {
      return;
    }
    unawaited(_openSession());
  }

  void onRequest(TrackerInfo connection) {
    if (!_tunnelUp) {
      unawaited(flush());
      return;
    }
    _ensureSessionOpen();
    final now = DateTime.now();
    final existing = _open[connection.id];
    if (existing == null) {
      _open[connection.id] = _OpenConnection(connection, _profile(), now);
    } else {
      existing.refresh(connection, now);
    }
  }

  void onRequestTraffic(Map<String, RequestTraffic> traffic) {
    if (!_tunnelUp) {
      return;
    }
    _ensureSessionOpen();
    final now = DateTime.now();
    for (final MapEntry(key: id, value: totals) in traffic.entries) {
      _open[id]?.updateTraffic(totals.upload, totals.download, now);
    }
  }

  Future<void> onLiveConnections(List<TrackerInfo> connections) async {
    if (!_tunnelUp) {
      await flush();
      return;
    }
    _ensureSessionOpen();
    final now = DateTime.now();
    final live = <String>{};
    for (final connection in connections) {
      live.add(connection.id);
      final existing = _open[connection.id];
      if (existing == null) {
        _open[connection.id] = _OpenConnection(connection, _profile(), now);
      } else {
        existing.refresh(connection, now);
      }
    }
    final closed = [
      for (final open in _open.values)
        if (!live.contains(open.connection.id)) open,
    ];
    for (final open in closed) {
      _open.remove(open.connection.id);
    }
    if (closed.isNotEmpty) {
      await _record(closed);
    }
    await _pruneIfDue(now);
    _invalidateStatistics(now);
  }

  /// Writes every still-open connection with the traffic seen so far, as
  /// of its last sighting.
  Future<void> flush() {
    if (!_tunnelUp) {
      unawaited(_closeSession());
    }
    if (_open.isEmpty) {
      return _writes;
    }
    final closed = _open.values.toList();
    _open.clear();
    return _record(closed);
  }

  (int, String) _profile() {
    final profile = ref.read(currentProfileProvider);
    return (profile?.id ?? 0, profile?.realLabel ?? '');
  }

  Future<void> _record(List<_OpenConnection> closed) {
    final run = _writes.then((_) async {
      try {
        await database.trafficStatisticsDao.recordClosed([
          for (final open in closed) open.toCompanion(),
        ]);
      } catch (error) {
        commonPrint.log(
          'Traffic statistics record failed: ${compactError(error)}',
          logLevel: LogLevel.warning,
        );
      }
    });
    _writes = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// Reopens a live session after the wipe, or uptime stalls on a deleted row.
  Future<void> clear() {
    final run = _writes.then((_) async {
      _open.clear();
      _openSessionId = null;
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

class _OpenConnection {
  _OpenConnection(this.connection, this.profile, this.lastSeenAt);

  TrackerInfo connection;
  final (int, String) profile;
  DateTime lastSeenAt;

  void refresh(TrackerInfo next, DateTime at) {
    connection = next;
    lastSeenAt = at;
  }

  void updateTraffic(int upload, int download, DateTime at) {
    connection = connection.copyWith(upload: upload, download: download);
    lastSeenAt = at;
  }

  TrafficStatisticsCompanion toCompanion() {
    final chains = connection.chains;
    return TrafficStatisticsCompanion.insert(
      connectionId: connection.id,
      host: connection.title,
      process: connection.metadata.process,
      proxy: chains.isEmpty ? '' : chains.last,
      direct: chains.firstOrNull == 'DIRECT',
      rule: connection.rule,
      rulePayload: connection.rulePayload,
      upload: connection.upload,
      download: connection.download,
      startedAt: connection.start,
      endedAt: lastSeenAt,
      profileId: profile.$1,
      profileLabel: profile.$2,
    );
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
    dao.rankBy(TrafficStatisticsRankBy.proxy, start, end),
    dao.rankBy(TrafficStatisticsRankBy.profile, start, end),
    dao.rankBy(TrafficStatisticsRankBy.rule, start, end),
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
    proxies: results[4] as List<TrafficStatisticsRank>,
    profiles: results[5] as List<TrafficStatisticsRank>,
    rules: results[6] as List<TrafficStatisticsRank>,
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
