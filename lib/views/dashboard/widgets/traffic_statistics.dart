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
      trafficStatisticsProvider(TrafficStatisticsRange.day),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(
          data.total.traffic.show,
          maxLines: 1,
          style: DashboardText.figure(context, AppTextStyle.title2),
        ),
        Text(
          '${appLocalizations.upload} ${data.upload.traffic.show} · '
          '${appLocalizations.download} ${data.download.traffic.show}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashboardText.label(context),
        ),
        Text(
          appLocalizations.trafficStatisticsToday,
          maxLines: 1,
          style: DashboardText.label(context),
        ),
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
