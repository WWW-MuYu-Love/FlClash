import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/traffic_statistics.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/views/traffic_statistics.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';

class TrafficStatisticsCard extends ConsumerWidget {
  const TrafficStatisticsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final statistics = ref.watch(
      trafficStatisticsProvider(TrafficStatisticsRange.day, 0),
    );
    return DashboardCard(
      semanticLabel: appLocalizations.trafficStatistics,
      onTap: () =>
          unawaited(BaseNavigator.push(context, const TrafficStatisticsView())),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.dataUsage,
            title: appLocalizations.trafficStatistics,
            chevron: true,
          ),
          const SizedBox(height: 12),
          statistics.when(
            data: (data) => _TodayFigures(data: data),
            loading: () => const _Placeholder(),
            error: (_, _) => const _Placeholder(),
          ),
        ],
      ),
    );
  }
}

class _TodayFigures extends StatelessWidget {
  const _TodayFigures({required this.data});

  final TrafficStatisticsData data;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    final total = data.total;
    final proxyBytes = data.proxyUpload + data.proxyDownload;
    final directBytes = data.directUpload + data.directDownload;
    final proxyRatio = total == 0 ? 0.0 : proxyBytes / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    total.traffic.show,
                    maxLines: 1,
                    style: DashboardText.figure(context, AppTextStyle.title2),
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
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _SplitGroup(
                        color: colorScheme.primary,
                        label: appLocalizations.trafficStatisticsProxy,
                        value: proxyBytes.traffic.show,
                      ),
                      _SplitGroup(
                        color: colors.series2,
                        label: appLocalizations.direct,
                        value: directBytes.traffic.show,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ProxyRatioRing(
              ratio: proxyRatio,
              size: 64,
              strokeWidth: 6,
              child: Text(
                '${(proxyRatio * 100).round()}%',
                maxLines: 1,
                style: AppTextStyle.subheadline.of(context, emphasized: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            GlyphIcon(
              AppGlyphs.clock,
              size: 14,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${appLocalizations.trafficStatisticsUptime} '
                '${trafficStatisticsUptimeText(appLocalizations.hours, appLocalizations.minutes, data.uptime)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardText.label(context),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SplitGroup extends StatelessWidget {
  const _SplitGroup({
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: ShapeDecoration(color: color, shape: AppShape.full),
        ),
        const SizedBox(width: 4),
        Text(label, style: DashboardText.label(context)),
        const SizedBox(width: 4),
        Text(value, style: DashboardText.label(context)),
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(
          '—',
          maxLines: 1,
          style: DashboardText.figure(
            context,
            AppTextStyle.title2,
          ).copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
        Text(
          context.appLocalizations.trafficStatisticsToday,
          maxLines: 1,
          style: DashboardText.label(context),
        ),
      ],
    );
  }
}
