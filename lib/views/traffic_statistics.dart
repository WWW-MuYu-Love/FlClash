import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/traffic_statistics.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _RankingTab { domain, proxy, profile, rule }

class TrafficStatisticsView extends ConsumerStatefulWidget {
  const TrafficStatisticsView({super.key});

  @override
  ConsumerState<TrafficStatisticsView> createState() =>
      _TrafficStatisticsViewState();
}

class _TrafficStatisticsViewState extends ConsumerState<TrafficStatisticsView> {
  var _range = TrafficStatisticsRange.day;
  var _offset = 0;
  var _rankingTab = _RankingTab.domain;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final statistics = ref.watch(trafficStatisticsProvider(_range, _offset));
    return Scaffold(
      title: appLocalizations.trafficStatistics,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.refresh,
          tooltip: appLocalizations.trafficStatisticsRefresh,
          onPressed: () =>
              ref.invalidate(trafficStatisticsProvider(_range, _offset)),
        ),
      ],
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
              onChanged: (range) => setState(() {
                _range = range;
                _offset = 0;
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: _offset >= maxTrafficStatisticsOffset(_range)
                      ? null
                      : () => setState(() => _offset++),
                  icon: const GlyphIcon(AppGlyphs.chevronBack, size: 20),
                  tooltip: appLocalizations.trafficStatisticsPrevious,
                ),
                Expanded(
                  child: Text(
                    trafficStatisticsRangeLabel(_range, _offset),
                    textAlign: TextAlign.center,
                    style: AppTextStyle.subheadline.of(context),
                  ),
                ),
                IconButton(
                  onPressed: _offset == 0
                      ? null
                      : () => setState(() => _offset--),
                  icon: const GlyphIcon(AppGlyphs.chevronForward, size: 20),
                  tooltip: appLocalizations.trafficStatisticsNext,
                ),
              ],
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
      _RankingTab.proxy => data.proxies,
      _RankingTab.profile => data.profiles,
      _RankingTab.rule => data.rules,
    };
    final glyph = switch (_rankingTab) {
      _RankingTab.domain => AppGlyphs.requests,
      _RankingTab.proxy => AppGlyphs.proxies,
      _RankingTab.profile => AppGlyphs.profiles,
      _RankingTab.rule => AppGlyphs.rules,
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
              Card(
                inert: true,
                padding: const EdgeInsets.all(16),
                child: _Overview(data: data),
              ),
            ],
          ),
          generateSection(
            title: appLocalizations.trafficStatisticsTrend,
            items: [
              Card(
                inert: true,
                padding: const EdgeInsets.all(16),
                child: _TrendChart(data: data),
              ),
            ],
          ),
          if (data.ruleHits.isNotEmpty) ...[
            ListHeader(title: appLocalizations.trafficStatisticsRuleHits),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                height: 116,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemCount: data.ruleHits.length,
                  itemBuilder: (context, index) {
                    final hit = data.ruleHits[index];
                    return SizedBox(
                      width: 220,
                      child: _RuleHitCard(
                        rank: hit,
                        ratio: data.totalRuleHits == 0
                            ? 0
                            : hit.hits / data.totalRuleHits,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
          ListHeader(title: appLocalizations.trafficStatisticsRankings),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: SegmentedControl<_RankingTab>(
              segments: [
                (_RankingTab.domain, appLocalizations.domain),
                (_RankingTab.proxy, appLocalizations.trafficStatisticsProxy),
                (_RankingTab.profile, appLocalizations.profile),
                (_RankingTab.rule, appLocalizations.rule),
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
            Card(
              inert: true,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (index, rank) in rankings.indexed) ...[
                    if (index > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 64),
                        child: Container(
                          height: 1,
                          color: Divider.colorOf(context),
                        ),
                      ),
                    _RankRow(
                      rank: rank,
                      ratio: data.total == 0 ? 0 : rank.bytes / data.total,
                      glyph: glyph,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.data});

  final TrafficStatisticsData data;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final total = data.total;
    final proxyBytes = data.proxyUpload + data.proxyDownload;
    final proxyRatio = total == 0 ? 0.0 : proxyBytes / total;
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appLocalizations.total,
                    style: AppTextStyle.subheadline
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    total.traffic.show,
                    style: AppTextStyle.title1.of(context, emphasized: true),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      TrafficStatisticsPill(
                        label: '↓ ${data.download.traffic.show}',
                      ),
                      TrafficStatisticsPill(
                        label: '↑ ${data.upload.traffic.show}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _ProxyGauge(ratio: proxyRatio),
          ],
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            spacing: 12,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _UptimeCell(uptime: data.uptime)),
              Expanded(child: _SplitCell(data: data)),
            ],
          ),
        ),
      ],
    );
  }
}

class TrafficStatisticsPill extends StatelessWidget {
  const TrafficStatisticsPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = DashboardColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(color: colors.tone, shape: AppShape.full),
      child: Text(
        label,
        style: AppTextStyle.footnote
            .of(context)
            .copyWith(color: context.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _ProxyGauge extends StatelessWidget {
  const _ProxyGauge({required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return ProxyRatioRing(
      ratio: ratio,
      size: 96,
      strokeWidth: 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${(ratio * 100).round()}%',
            style: AppTextStyle.headline.of(context, emphasized: true),
          ),
          Text(
            context.appLocalizations.trafficStatisticsProxy,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _UptimeCell extends StatelessWidget {
  const _UptimeCell({required this.uptime});

  final Duration uptime;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ShapeDecoration(
        color: DashboardColors.of(context).tone,
        shape: AppShape.all(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlyphIcon(
                AppGlyphs.clock,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  appLocalizations.trafficStatisticsUptime,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.subheadline
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            trafficStatisticsUptimeText(
              appLocalizations.hours,
              appLocalizations.minutes,
              uptime,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.title3.of(context, emphasized: true),
          ),
        ],
      ),
    );
  }
}

String trafficStatisticsUptimeText(
  String hoursLabel,
  String minutesLabel,
  Duration uptime,
) {
  final hours = uptime.inHours;
  final minutes = uptime.inMinutes.remainder(60);
  if (hours > 0 && minutes > 0) {
    return '$hours $hoursLabel $minutes $minutesLabel';
  }
  if (hours > 0) {
    return '$hours $hoursLabel';
  }
  return '$minutes $minutesLabel';
}

class _SplitCell extends StatelessWidget {
  const _SplitCell({required this.data});

  final TrafficStatisticsData data;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ShapeDecoration(color: colors.tone, shape: AppShape.all(12)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _SplitRow(
            color: colorScheme.primary,
            label: appLocalizations.trafficStatisticsProxy,
            value: (data.proxyUpload + data.proxyDownload).traffic.show,
          ),
          const SizedBox(height: 8),
          _SplitRow(
            color: colors.series2,
            label: appLocalizations.direct,
            value: (data.directUpload + data.directDownload).traffic.show,
          ),
        ],
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: ShapeDecoration(color: color, shape: AppShape.full),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.subheadline.of(context),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          maxLines: 1,
          style: AppTextStyle.subheadline.of(context, emphasized: true),
        ),
      ],
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.data});

  static const _height = 120.0;

  final TrafficStatisticsData data;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    final buckets = data.trend;
    final max = buckets.fold<int>(
      0,
      (peak, bucket) => math.max(peak, bucket.upload + bucket.download),
    );
    return Column(
      children: [
        Row(
          children: [
            const Spacer(),
            _LegendDot(
              color: colorScheme.primary,
              label: appLocalizations.download,
            ),
            const SizedBox(width: 12),
            _LegendDot(color: colors.series2, label: appLocalizations.upload),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (var i = 0; i < 3; i++)
                            Container(
                              height: 1,
                              color: Divider.colorOf(context),
                            ),
                        ],
                      ),
                    ),
                    Positioned.fill(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        spacing: 2,
                        children: [
                          for (final bucket in buckets)
                            Expanded(
                              child: _TrendBar(
                                bucket: bucket,
                                max: max,
                                downloadColor: colorScheme.primary,
                                uploadColor: colors.series2,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 52,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _AxisLabel(max.traffic.show),
                    _AxisLabel((max ~/ 2).traffic.show),
                    const _AxisLabel('0'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final label in _xLabels(data))
                    Text(
                      label,
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 60),
          ],
        ),
      ],
    );
  }
}

class _TrendBar extends StatelessWidget {
  const _TrendBar({
    required this.bucket,
    required this.max,
    required this.downloadColor,
    required this.uploadColor,
  });

  final TrafficStatisticsBucket bucket;
  final int max;
  final Color downloadColor;
  final Color uploadColor;

  @override
  Widget build(BuildContext context) {
    final (download, upload) = _stackedHeights(bucket, max);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      spacing: 2,
      children: [
        _TrendSegment(height: upload, color: uploadColor),
        _TrendSegment(height: download, color: downloadColor),
      ],
    );
  }
}

class _TrendSegment extends StatelessWidget {
  const _TrendSegment({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (height <= 0) {
      return const SizedBox.shrink();
    }
    return Container(
      height: height,
      decoration: ShapeDecoration(color: color, shape: AppShape.all(3)),
    );
  }
}

(double, double) _stackedHeights(TrafficStatisticsBucket bucket, int max) {
  final total = bucket.upload + bucket.download;
  if (max == 0 || total == 0) {
    return (0, 0);
  }
  final both = bucket.upload > 0 && bucket.download > 0;
  final available = both ? _TrendChart._height - 2 : _TrendChart._height;
  final totalHeight = total / max * available;
  var download = totalHeight * bucket.download / total;
  var upload = totalHeight - download;
  if (download > 0 && download < 2) {
    download = 2;
    upload = totalHeight - download;
  }
  if (upload > 0 && upload < 2) {
    upload = 2;
    download = totalHeight - upload;
  }
  return (math.max(0, download), math.max(0, upload));
}

List<String> _xLabels(TrafficStatisticsData data) {
  final buckets = data.trend;
  if (buckets.isEmpty) {
    return const [];
  }
  if (data.range == TrafficStatisticsRange.day) {
    return const ['0', '6', '12', '18'];
  }
  String label(DateTime date) =>
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
  if (buckets.length == 1) {
    return [label(buckets.first.start)];
  }
  return [
    label(buckets.first.start),
    label(buckets[buckets.length ~/ 2].start),
    label(buckets.last.start),
  ];
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: ShapeDecoration(color: color, shape: AppShape.full),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTextStyle.footnote
              .of(context)
              .copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _AxisLabel extends StatelessWidget {
  const _AxisLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyle.footnote
          .of(context)
          .copyWith(color: context.colorScheme.onSurfaceVariant),
    );
  }
}

class _RuleHitCard extends StatelessWidget {
  const _RuleHitCard({required this.rank, required this.ratio});

  final TrafficStatisticsRank rank;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    final ruleType = rank.ruleType;
    return Card(
      inert: true,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProxyRatioRing(
                ratio: ratio,
                size: 44,
                strokeWidth: 4,
                child: Text(
                  '${(ratio * 100).round()}%',
                  maxLines: 1,
                  style: AppTextStyle.caption1.of(context, emphasized: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  rank.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.subheadline.of(context, emphasized: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: Divider.colorOf(context)),
          const SizedBox(height: 8),
          Row(
            children: [
              if (ruleType != null && ruleType.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: ShapeDecoration(
                    color: colors.tone,
                    shape: AppShape.full,
                  ),
                  child: Text(
                    ruleType,
                    maxLines: 1,
                    style: AppTextStyle.caption1
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              const Spacer(),
              Flexible(
                child: Text(
                  '${appLocalizations.trafficStatisticsHits(rank.hits)} · '
                  '${rank.bytes.traffic.show}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ProxyRatioRing extends StatelessWidget {
  const ProxyRatioRing({
    super.key,
    required this.ratio,
    required this.size,
    required this.strokeWidth,
    required this.child,
  });

  final double ratio;
  final double size;
  final double strokeWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: ProxyRatioRingPainter(
          ratio: ratio,
          color: colorScheme.primary,
          trackColor: DashboardColors.of(context).tone2,
          strokeWidth: strokeWidth,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class ProxyRatioRingPainter extends CustomPainter {
  ProxyRatioRingPainter({
    required this.ratio,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double ratio;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.shortestSide - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, track);
    if (ratio <= 0) {
      return;
    }
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      ratio.clamp(0, 1) * 2 * math.pi,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(ProxyRatioRingPainter old) =>
      old.ratio != ratio ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.ratio,
    required this.glyph,
  });

  final TrafficStatisticsRank rank;
  final double ratio;
  final Glyph glyph;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: ShapeDecoration(
              color: colors.tone,
              shape: AppShape.all(10),
            ),
            alignment: Alignment.center,
            child: GlyphIcon(
              glyph,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        rank.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.subheadline.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      rank.bytes.traffic.show,
                      maxLines: 1,
                      style: AppTextStyle.subheadline.of(
                        context,
                        emphasized: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 4,
                  decoration: ShapeDecoration(
                    color: colors.tone2,
                    shape: AppShape.full,
                  ),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: ratio.clamp(0, 1),
                    child: Container(
                      decoration: ShapeDecoration(
                        color: colorScheme.primary,
                        shape: AppShape.full,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '↓ ${rank.download.traffic.show}  '
                      '↑ ${rank.upload.traffic.show}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const Spacer(),
                    Text(
                      '${(ratio * 100).toStringAsFixed(1)}%',
                      maxLines: 1,
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
