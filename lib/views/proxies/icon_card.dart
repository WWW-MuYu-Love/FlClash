import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'common.dart';

const _cardInset = 12.0;
const _nameIconGap = 8.0;
const _metaGap = 6.0;
const _bottomGap = 8.0;
const _expandIconSize = 24.0;

/// The header height the grid's sliver offsets are measured with; it has to
/// match the card below.
double get groupIconCardHeight {
  final measure = globalState.measure;
  return _cardInset * 2 +
      groupBrandIconSize +
      _metaGap +
      measure.textHeight(AppTextStyle.caption1) +
      _bottomGap +
      _expandIconSize;
}

class GroupIconCard extends ConsumerWidget {
  const GroupIconCard({
    super.key,
    required this.group,
    required this.isExpand,
    required this.unfolded,
    this.floating = 0,
    this.lift = 0,
    required this.onChange,
    required this.onDelayTest,
  });

  final Group group;
  final bool isExpand;
  final bool unfolded;
  final double floating;
  final double lift;
  final VoidCallback onChange;
  final VoidCallback onDelayTest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupName = group.name;
    final colorScheme = context.colorScheme;
    final level = floating > 0
        ? SurfaceLevel.floatingOf(colorScheme)
        : context.raisedSurfaceLevel;
    final radius = AppCorner.xl.ap(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: level.colorOf(colorScheme),
        shape: AppShape.vertical(
          top: radius,
          bottom: unfolded ? radius * floating : radius,
        ),
        shadows: lift == 0 ? null : floatingShadows(colorScheme, lift),
      ),
      child: Padding(
        padding: const EdgeInsets.all(groupHeaderButtonInset),
        child: SurfaceScope(
          // Card fills one level above its scope.
          level: SurfaceLevel.values[level.index - 1],
          child: Card(
            enterActionsOnRight: true,
            enterAnimated: false,
            radius: radius - groupHeaderButtonInset,
            onPressed: onChange,
            child: Padding(
              padding: const EdgeInsets.all(_cardInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: EmojiText(
                          groupName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.callout.of(
                            context,
                            emphasized: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: _nameIconGap),
                      GroupBrandIcon(src: group.icon, name: groupName),
                    ],
                  ),
                  const SizedBox(height: _metaGap),
                  Text(
                    '${group.type.value.toUpperCase()} · ${group.all.length}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption1.of(context).toLight,
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Flexible(child: _SelectedProxyName(groupName: groupName)),
                      _SelectedDelay(group: group, onDelayTest: onDelayTest),
                      const SizedBox(width: 6),
                      SizedBox.square(
                        dimension: _expandIconSize,
                        child: IconTheme.merge(
                          data: const IconThemeData(size: _expandIconSize),
                          child: ExpandIcon(expand: isExpand),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedProxyName extends ConsumerWidget {
  const _SelectedProxyName({required this.groupName});

  final String groupName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxyName = ref
        .watch(selectedProxyNameProvider(groupName))
        .takeFirstValid([]);
    if (proxyName.isEmpty) {
      return const SizedBox.shrink();
    }
    return EmojiText(
      proxyName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyle.caption1.of(context, emphasized: true).toLight,
    );
  }
}

/// The selected node's delay as a pill; tapping it tests the group, the
/// same test the list header's bolt button runs.
class _SelectedDelay extends ConsumerWidget {
  const _SelectedDelay({required this.group, required this.onDelayTest});

  final Group group;
  final VoidCallback onDelayTest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupName = group.name;
    final proxyName = ref
        .watch(selectedProxyNameProvider(groupName))
        .takeFirstValid([]);
    if (proxyName.isEmpty) {
      return const SizedBox.shrink();
    }
    final isDelayTesting = ref.watch(
      delayTestingGroupsProvider.select((state) => state.contains(groupName)),
    );
    final delay = ref.watch(
      delayProvider(proxyName: proxyName, testUrl: group.testUrl),
    );
    final colorScheme = context.colorScheme;
    final color = colorScheme.delayColor(delay) ?? colorScheme.onSurfaceVariant;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isDelayTesting ? null : onDelayTest,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: color.opacity15,
          shape: AppShape.full,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: isDelayTesting
              ? const ActivityIndicator(size: 14)
              : delay == null
              ? GlyphIcon(AppGlyphs.bolt, size: 14, color: color)
              : Text(
                  delay > 0
                      ? '$delay ms'
                      : delayFailureText(delay, context.appLocalizations),
                  maxLines: 1,
                  style: AppTextStyle.caption2
                      .of(context, emphasized: true)
                      .copyWith(color: color),
                ),
        ),
      ),
    );
  }
}
