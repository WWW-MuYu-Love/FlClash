part of 'database.dart';

/// How long a closed connection's traffic is kept.
const trafficStatisticsRetention = Duration(days: 90);

/// One closed connection's traffic, as the recorder saw it when the
/// connection left the live list.
@DataClassName('TrafficStatisticsRecord')
@TableIndex(name: 'idx_traffic_statistics_ended_at', columns: {#endedAt})
class TrafficStatistics extends Table {
  @override
  String get tableName => 'traffic_statistics';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get connectionId => text()();

  TextColumn get host => text()();

  TextColumn get process => text()();

  TextColumn get proxy => text()();

  /// The egress node the connection actually left through: the first
  /// entry of the core's chain. The `proxy` column holds the outermost
  /// group instead, so rows recorded before this column existed have no
  /// node and stay out of the node ranking.
  TextColumn get node => text().nullable()();

  BoolColumn get direct => boolean()();

  TextColumn get rule => text()();

  TextColumn get rulePayload => text()();

  IntColumn get upload => integer()();

  IntColumn get download => integer()();

  DateTimeColumn get startedAt => dateTime()();

  DateTimeColumn get endedAt => dateTime()();

  IntColumn get profileId => integer()();

  TextColumn get profileLabel => text()();
}

/// One tunnel session: opened when the tunnel comes up, closed when it
/// goes down. A session left open by a killed process is closed when the
/// next one opens, so its time still counts contiguously.
@DataClassName('TunnelSessionRecord')
class TunnelSessions extends Table {
  @override
  String get tableName => 'tunnel_sessions';

  IntColumn get id => integer().autoIncrement()();

  DateTimeColumn get startedAt => dateTime()();

  DateTimeColumn get endedAt => dateTime().nullable()();
}

enum TrafficStatisticsRankBy { domain, process, policy, node, profile }

class TrafficStatisticsTotals {
  const TrafficStatisticsTotals({
    required this.count,
    required this.upload,
    required this.download,
    required this.directUpload,
    required this.directDownload,
  });

  final int count;
  final int upload;
  final int download;
  final int directUpload;
  final int directDownload;
}

class TrafficStatisticsBucket {
  const TrafficStatisticsBucket({
    required this.start,
    required this.upload,
    required this.download,
  });

  final DateTime start;
  final int upload;
  final int download;
}

class TrafficStatisticsRank {
  const TrafficStatisticsRank({
    required this.label,
    required this.bytes,
    required this.hits,
    this.upload = 0,
    this.download = 0,
    this.ruleType,
  });

  final String label;
  final int bytes;
  final int hits;
  final int upload;
  final int download;
  final String? ruleType;
}

@DriftAccessor(tables: [TunnelSessions])
class TunnelSessionsDao extends DatabaseAccessor<Database>
    with _$TunnelSessionsDaoMixin {
  TunnelSessionsDao(super.attachedDatabase);

  Future<int> openSession(DateTime startedAt) {
    return into(
      tunnelSessions,
    ).insert(TunnelSessionsCompanion.insert(startedAt: startedAt));
  }

  Future<void> closeOpenSessions(DateTime endedAt) {
    return (update(tunnelSessions)..where((t) => t.endedAt.isNull())).write(
      TunnelSessionsCompanion(endedAt: Value(endedAt)),
    );
  }

  Future<Duration> uptime(DateTime start, DateTime end) async {
    final rows = await customSelect(
      'SELECT started_at, ended_at FROM tunnel_sessions '
      'WHERE started_at < ? AND (ended_at IS NULL OR ended_at > ?)',
      variables: [Variable.withDateTime(end), Variable.withDateTime(start)],
    ).get();
    var total = Duration.zero;
    for (final row in rows) {
      final sessionStart = row.read<DateTime>('started_at');
      final sessionEnd = row.readNullable<DateTime>('ended_at') ?? end;
      final overlapStart = sessionStart.isAfter(start) ? sessionStart : start;
      final overlapEnd = sessionEnd.isBefore(end) ? sessionEnd : end;
      if (overlapEnd.isAfter(overlapStart)) {
        total += overlapEnd.difference(overlapStart);
      }
    }
    return total;
  }

  Future<int> pruneClosedBefore(DateTime cutoff) {
    return (delete(tunnelSessions)..where(
          (t) => t.endedAt.isNotNull() & t.endedAt.isSmallerThanValue(cutoff),
        ))
        .go();
  }

  Future<int> clear() {
    return delete(tunnelSessions).go();
  }
}

@DriftAccessor(tables: [TrafficStatistics])
class TrafficStatisticsDao extends DatabaseAccessor<Database>
    with _$TrafficStatisticsDaoMixin {
  TrafficStatisticsDao(super.attachedDatabase);

  Future<void> recordClosed(List<TrafficStatisticsCompanion> rows) {
    if (rows.isEmpty) {
      return Future.value();
    }
    return attachedDatabase.batch(
      (batch) => batch.insertAll(trafficStatistics, rows),
    );
  }

  Future<int> pruneOlderThan(DateTime cutoff) {
    return trafficStatistics.remove(
      (t) => t.endedAt.isSmallerThanValue(cutoff),
    );
  }

  Future<int> clear() {
    return delete(trafficStatistics).go();
  }

  Future<TrafficStatisticsTotals> totals(DateTime start, DateTime end) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS count, '
      'COALESCE(SUM(upload), 0) AS upload, '
      'COALESCE(SUM(download), 0) AS download, '
      'COALESCE(SUM(CASE WHEN direct = 1 THEN upload ELSE 0 END), 0) '
      'AS direct_upload, '
      'COALESCE(SUM(CASE WHEN direct = 1 THEN download ELSE 0 END), 0) '
      'AS direct_download '
      'FROM traffic_statistics WHERE ended_at >= ? AND ended_at < ?',
      variables: [Variable.withDateTime(start), Variable.withDateTime(end)],
    ).getSingle();
    return TrafficStatisticsTotals(
      count: row.read<int>('count'),
      upload: row.read<int>('upload'),
      download: row.read<int>('download'),
      directUpload: row.read<int>('direct_upload'),
      directDownload: row.read<int>('direct_download'),
    );
  }

  Future<List<TrafficStatisticsBucket>> trend(
    DateTime start,
    DateTime end, {
    required bool hourly,
  }) async {
    final bucket = hourly
        ? "strftime('%Y-%m-%d %H:00:00', ended_at, 'unixepoch', "
              "'localtime')"
        : "strftime('%Y-%m-%d', ended_at, 'unixepoch', 'localtime')";
    final rows = await customSelect(
      'SELECT $bucket AS bucket, '
      'COALESCE(SUM(upload), 0) AS upload, '
      'COALESCE(SUM(download), 0) AS download '
      'FROM traffic_statistics WHERE ended_at >= ? AND ended_at < ? '
      'GROUP BY bucket ORDER BY bucket',
      variables: [Variable.withDateTime(start), Variable.withDateTime(end)],
    ).get();
    return [
      for (final row in rows)
        TrafficStatisticsBucket(
          start: DateTime.parse(row.read<String>('bucket')),
          upload: row.read<int>('upload'),
          download: row.read<int>('download'),
        ),
    ];
  }

  Future<List<TrafficStatisticsRank>> ruleHits(
    DateTime start,
    DateTime end, {
    int limit = 10,
  }) async {
    final rows = await customSelect(
      'SELECT rule AS rule_type, '
      "CASE WHEN rule_payload != '' THEN rule_payload ELSE rule END "
      'AS label, COUNT(*) AS hits, '
      'COALESCE(SUM(upload + download), 0) AS bytes '
      'FROM traffic_statistics WHERE ended_at >= ? AND ended_at < ? '
      'GROUP BY rule, label ORDER BY hits DESC, bytes DESC LIMIT ?',
      variables: [
        Variable.withDateTime(start),
        Variable.withDateTime(end),
        Variable.withInt(limit),
      ],
    ).get();
    return [
      for (final row in rows)
        TrafficStatisticsRank(
          label: row.read<String>('label'),
          bytes: row.read<int>('bytes'),
          hits: row.read<int>('hits'),
          ruleType: row.read<String>('rule_type'),
        ),
    ];
  }

  Future<List<TrafficStatisticsRank>> rankBy(
    TrafficStatisticsRankBy by,
    DateTime start,
    DateTime end, {
    int limit = 10,
  }) async {
    final (groupBy, exclusion) = switch (by) {
      TrafficStatisticsRankBy.domain => ('host', ''),
      TrafficStatisticsRankBy.process => ('process', ''),
      TrafficStatisticsRankBy.policy => (
        'proxy',
        " AND proxy NOT IN ('DIRECT', 'REJECT')",
      ),
      TrafficStatisticsRankBy.node => (
        'node',
        " AND node NOT IN ('DIRECT', 'REJECT')",
      ),
      TrafficStatisticsRankBy.profile => ('profile_label', ''),
    };
    final rows = await customSelect(
      'SELECT $groupBy AS label, '
      'COALESCE(SUM(upload + download), 0) AS bytes, COUNT(*) AS hits, '
      'COALESCE(SUM(upload), 0) AS upload, '
      'COALESCE(SUM(download), 0) AS download '
      'FROM traffic_statistics '
      'WHERE ended_at >= ? AND ended_at < ? AND $groupBy != \'\'$exclusion '
      'GROUP BY $groupBy ORDER BY bytes DESC, hits DESC LIMIT ?',
      variables: [
        Variable.withDateTime(start),
        Variable.withDateTime(end),
        Variable.withInt(limit),
      ],
    ).get();
    return _ranksOf(rows);
  }

  List<TrafficStatisticsRank> _ranksOf(List<QueryRow> rows) {
    return [
      for (final row in rows)
        TrafficStatisticsRank(
          label: row.read<String>('label'),
          bytes: row.read<int>('bytes'),
          hits: row.read<int>('hits'),
          upload: row.read<int>('upload'),
          download: row.read<int>('download'),
        ),
    ];
  }
}
