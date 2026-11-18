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
    required this.trend,
    required this.ruleHits,
    required this.domains,
    required this.processes,
    required this.proxies,
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
  final List<TrafficStatisticsBucket> trend;
  final List<TrafficStatisticsRank> ruleHits;
  final List<TrafficStatisticsRank> domains;
  final List<TrafficStatisticsRank> processes;
  final List<TrafficStatisticsRank> proxies;
  final List<TrafficStatisticsRank> profiles;

  int get total => upload + download;

  int get proxyUpload => upload - directUpload;

  int get proxyDownload => download - directDownload;
}

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

  @override
  void build() {
    // Pruning waits for the first live snapshot: the database may not be
    // openable yet when this notifier is first read.
  }

  bool get _tunnelUp => ref.read(isStartProvider);

  void onRequest(TrackerInfo connection) {
    if (!_tunnelUp) {
      unawaited(flush());
      return;
    }
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
) async {
  final dao = database.trafficStatisticsDao;
  final now = DateTime.now();
  final (start, end, hourly) = _rangeWindow(range, now);
  await dao.pruneOlderThan(now.subtract(trafficStatisticsRetention));
  final results = await Future.wait([
    dao.totals(start, end),
    dao.trend(start, end, hourly: hourly),
    dao.ruleHits(start, end),
    dao.rankBy(TrafficStatisticsRankBy.domain, start, end),
    dao.rankBy(TrafficStatisticsRankBy.process, start, end),
    dao.rankBy(TrafficStatisticsRankBy.proxy, start, end),
    dao.rankBy(TrafficStatisticsRankBy.profile, start, end),
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
    trend: _fillTrend(start, end, hourly, buckets),
    ruleHits: results[2] as List<TrafficStatisticsRank>,
    domains: results[3] as List<TrafficStatisticsRank>,
    processes: results[4] as List<TrafficStatisticsRank>,
    proxies: results[5] as List<TrafficStatisticsRank>,
    profiles: results[6] as List<TrafficStatisticsRank>,
  );
}

(DateTime, DateTime, bool) _rangeWindow(
  TrafficStatisticsRange range,
  DateTime now,
) {
  final dayStart = DateTime(now.year, now.month, now.day);
  return switch (range) {
    TrafficStatisticsRange.day => (dayStart, now, true),
    TrafficStatisticsRange.week => (
      dayStart.subtract(Duration(days: now.weekday - 1)),
      now,
      false,
    ),
    TrafficStatisticsRange.month => (DateTime(now.year, now.month), now, false),
  };
}

List<TrafficStatisticsBucket> _fillTrend(
  DateTime start,
  DateTime end,
  bool hourly,
  List<TrafficStatisticsBucket> buckets,
) {
  final byStart = {for (final bucket in buckets) bucket.start: bucket};
  final trend = <TrafficStatisticsBucket>[];
  var cursor = hourly
      ? DateTime(start.year, start.month, start.day, start.hour)
      : DateTime(start.year, start.month, start.day);
  final last = hourly
      ? DateTime(end.year, end.month, end.day, end.hour)
      : DateTime(end.year, end.month, end.day);
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
