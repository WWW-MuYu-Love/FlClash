import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/traffic_statistics.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _RankingTab { domain, process, proxy, profile }

class TrafficStatisticsView extends ConsumerStatefulWidget {
  const TrafficStatisticsView({super.key});

  @override
  ConsumerState<TrafficStatisticsView> createState() =>
      _TrafficStatisticsViewState();
}

class _TrafficStatisticsViewState extends ConsumerState<TrafficStatisticsView> {
  var _range = TrafficStatisticsRange.day;
  var _rankingTab = _RankingTab.domain;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final statistics = ref.watch(trafficStatisticsProvider(_range));
    return Scaffold(
      title: appLocalizations.trafficStatistics,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, context.contentTopPadding, 16, 0),
            child: SegmentedControl<TrafficStatisticsRange>(
              segments: [
                (
                  TrafficStatisticsRange.day,
                  appLocalizations.trafficStatisticsDay,
                ),
                (
                  TrafficStatisticsRange.week,
                  appLocalizations.trafficStatisticsWeek,
                ),
                (
                  TrafficStatisticsRange.month,
                  appLocalizations.trafficStatisticsMonth,
                ),
              ],
              value: _range,
              onChanged: (range) => setState(() => _range = range),
            ),
          ),
          Expanded(
            child: statistics.when(
              data: (data) => _buildBody(context, data),
              loading: () => const Center(child: ActivityIndicator(size: 24)),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '$error',
                    textAlign: TextAlign.center,
                    style: AppTextStyle.subheadline
                        .of(context)
                        .copyWith(color: context.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, TrafficStatisticsData data) {
    final appLocalizations = context.appLocalizations;
    if (data.count == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            appLocalizations.trafficStatisticsNoData,
            textAlign: TextAlign.center,
            style: AppTextStyle.subheadline
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    final rankings = switch (_rankingTab) {
      _RankingTab.domain => data.domains,
      _RankingTab.process => data.processes,
      _RankingTab.proxy => data.proxies,
      _RankingTab.profile => data.profiles,
    };
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 20 + context.bottomInset,
      ),
      child: Column(
        children: [
          generateSection(
            title: appLocalizations.overview,
            items: [
              _InfoRow(
                label: appLocalizations.total,
                value: data.total.traffic.show,
              ),
              _InfoRow(
                label: appLocalizations.upload,
                value: data.upload.traffic.show,
              ),
              _InfoRow(
                label: appLocalizations.download,
                value: data.download.traffic.show,
              ),
              _InfoRow(
                label: appLocalizations.direct,
                value: (data.directUpload + data.directDownload).traffic.show,
              ),
              _InfoRow(
                label: appLocalizations.trafficStatisticsProxy,
                value: (data.proxyUpload + data.proxyDownload).traffic.show,
              ),
              _InfoRow(
                label: appLocalizations.connections,
                value: data.count.toString(),
              ),
            ],
          ),
          generateSection(
            title: appLocalizations.trafficStatisticsTrend,
            items: [_TrendChart(buckets: data.trend)],
          ),
          if (data.ruleHits.isNotEmpty)
            generateSection(
              title: appLocalizations.trafficStatisticsRuleHits,
              items: [
                for (final (index, rank) in data.ruleHits.indexed)
                  _RankRow(rank: rank, index: index),
              ],
            ),
          ListHeader(title: appLocalizations.trafficStatisticsRankings),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: SegmentedControl<_RankingTab>(
              segments: [
                (_RankingTab.domain, appLocalizations.domain),
                (_RankingTab.process, appLocalizations.process),
                (_RankingTab.proxy, appLocalizations.trafficStatisticsProxy),
                (_RankingTab.profile, appLocalizations.profile),
              ],
              value: _rankingTab,
              onChanged: (tab) => setState(() => _rankingTab = tab),
            ),
          ),
          if (rankings.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                appLocalizations.trafficStatisticsNoData,
                textAlign: TextAlign.center,
                style: AppTextStyle.subheadline
                    .of(context)
                    .copyWith(color: context.colorScheme.onSurfaceVariant),
              ),
            )
          else
            generateSection(
              items: [
                for (final (index, rank) in rankings.indexed)
                  _RankRow(rank: rank, index: index),
              ],
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListItem(
      title: Text(label),
      trailing: Text(
        value,
        style: AppTextStyle.subheadline
            .of(context)
            .copyWith(color: context.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.buckets});

  static const _height = 120.0;

  final List<TrafficStatisticsBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final max = buckets.fold<int>(
      0,
      (peak, bucket) => math.max(peak, bucket.upload + bucket.download),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SizedBox(
        height: _height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: 2,
          children: [
            for (final bucket in buckets)
              Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: max == 0
                        ? 0
                        : math.max(
                            2,
                            (bucket.upload + bucket.download) / max * _height,
                          ),
                    decoration: ShapeDecoration(
                      color: context.colorScheme.primary,
                      shape: AppShape.all(3),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.rank, required this.index});

  final TrafficStatisticsRank rank;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return ListItem(
      leading: SizedBox(
        width: 24,
        child: Text(
          '${index + 1}',
          style: AppTextStyle.subheadline
              .of(context)
              .copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ),
      title: Text(rank.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${rank.hits} ${context.appLocalizations.connections}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        rank.bytes.traffic.show,
        style: AppTextStyle.subheadline
            .of(context)
            .copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}
