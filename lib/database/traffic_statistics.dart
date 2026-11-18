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

enum TrafficStatisticsRankBy { domain, process, proxy, profile }

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
  });

  final String label;
  final int bytes;
  final int hits;
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
      'SELECT CASE WHEN rule_payload != \'\' THEN rule_payload ELSE rule END '
      'AS label, COUNT(*) AS hits, '
      'COALESCE(SUM(upload + download), 0) AS bytes '
      'FROM traffic_statistics WHERE ended_at >= ? AND ended_at < ? '
      'GROUP BY label ORDER BY hits DESC, bytes DESC LIMIT ?',
      variables: [
        Variable.withDateTime(start),
        Variable.withDateTime(end),
        Variable.withInt(limit),
      ],
    ).get();
    return _ranksOf(rows);
  }

  Future<List<TrafficStatisticsRank>> rankBy(
    TrafficStatisticsRankBy by,
    DateTime start,
    DateTime end, {
    int limit = 10,
  }) async {
    final column = switch (by) {
      TrafficStatisticsRankBy.domain => 'host',
      TrafficStatisticsRankBy.process => 'process',
      TrafficStatisticsRankBy.proxy => 'proxy',
      TrafficStatisticsRankBy.profile => 'profile_label',
    };
    final exclusion = by == TrafficStatisticsRankBy.proxy
        ? " AND $column NOT IN ('DIRECT', 'REJECT')"
        : '';
    final rows = await customSelect(
      'SELECT $column AS label, '
      'COALESCE(SUM(upload + download), 0) AS bytes, COUNT(*) AS hits '
      'FROM traffic_statistics '
      'WHERE ended_at >= ? AND ended_at < ? AND $column != \'\'$exclusion '
      'GROUP BY $column ORDER BY bytes DESC, hits DESC LIMIT ?',
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
        ),
    ];
  }
}
