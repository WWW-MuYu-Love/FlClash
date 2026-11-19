import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'common.dart';

const _bottomRowHeight = 24.0;
const _nowIconSize = 14.0;
const _nodeIconSize = 16.0;
const _nowGap = 4.0;
const _brandIconTilePadding = 6.0;
const _brandIconTileShrink = 12.0;

({
  double inset,
  double nameIconGap,
  double metaGap,
  double bottomGap,
  double brandIconSize,
})
_cardMetrics(ProxyCardType cardType) => switch (cardType) {
  ProxyCardType.compact => (
    inset: 8.0,
    nameIconGap: 6.0,
    metaGap: 4.0,
    bottomGap: 8.0,
    brandIconSize: 40.0,
  ),
  ProxyCardType.standard => (
    inset: 12.0,
    nameIconGap: 8.0,
    metaGap: 6.0,
    bottomGap: 8.0,
    brandIconSize: groupBrandIconSize,
  ),
  ProxyCardType.loose => (
    inset: 16.0,
    nameIconGap: 8.0,
    metaGap: 8.0,
    bottomGap: 10.0,
    brandIconSize: 56.0,
  ),
};

/// The header height the grid's sliver offsets are measured with; it has to
/// match the card below.
double groupIconCardHeightOf(
  ProxyCardType cardType,
  ProxiesIconStyle iconStyle,
) {
  final measure = globalState.measure;
  final metrics = _cardMetrics(cardType);
  final rowHeight = iconStyle == ProxiesIconStyle.hidden
      ? measure.textHeight(AppTextStyle.callout)
      : metrics.brandIconSize;
  return metrics.inset * 2 +
      rowHeight +
      metrics.metaGap +
      measure.textHeight(AppTextStyle.caption1) +
      metrics.bottomGap +
      _bottomRowHeight;
}

class GroupIconCard extends ConsumerWidget {
  const GroupIconCard({
    super.key,
    required this.group,
    required this.cardType,
    required this.iconStyle,
    required this.unfolded,
    this.floating = 0,
    this.lift = 0,
    required this.onChange,
    required this.onDelayTest,
    required this.searchKeyword,
    required this.searchOpen,
    required this.onSearchKeyword,
    required this.onSearchOpen,
  });

  final Group group;
  final ProxyCardType cardType;
  final ProxiesIconStyle iconStyle;
  final bool unfolded;
  final double floating;
  final double lift;
  final VoidCallback onChange;
  final VoidCallback onDelayTest;

  final String searchKeyword;
  final bool searchOpen;
  final ValueChanged<String> onSearchKeyword;
  final ValueChanged<bool> onSearchOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupName = group.name;
    final colorScheme = context.colorScheme;
    final level = floating > 0
        ? SurfaceLevel.floatingOf(colorScheme)
        : context.raisedSurfaceLevel;
    final radius = AppCorner.xl.ap(context);
    final metrics = _cardMetrics(cardType);
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
              padding: EdgeInsets.all(metrics.inset),
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
                      if (iconStyle != ProxiesIconStyle.hidden) ...[
                        SizedBox(width: metrics.nameIconGap),
                        _GroupBrandIcon(
                          src: group.icon,
                          name: groupName,
                          size: metrics.brandIconSize,
                          iconStyle: iconStyle,
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: metrics.metaGap),
                  Row(
                    children: [
                      Flexible(child: _GroupAvailability(group: group)),
                      if (unfolded) ...[
                        const SizedBox(width: 8),
                        GroupSearchControl(
                          keyword: searchKeyword,
                          open: searchOpen,
                          onKeyword: onSearchKeyword,
                          onOpen: onSearchOpen,
                        ),
                      ],
                    ],
                  ),
                  const Spacer(),
                  _GroupBottomRow(
                    group: group,
                    cardType: cardType,
                    iconStyle: iconStyle,
                    unfolded: unfolded,
                    onDelayTest: onDelayTest,
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

/// The group brand icon as the icon style renders it: a raised tile, the
/// bare icon, or nothing. The selected node's icon in the row below is the
/// group's current pick, not the group icon, so the style leaves it alone.
class _GroupBrandIcon extends StatelessWidget {
  const _GroupBrandIcon({
    required this.src,
    required this.name,
    required this.size,
    required this.iconStyle,
  });

  final String src;
  final String name;
  final double size;
  final ProxiesIconStyle iconStyle;

  @override
  Widget build(BuildContext context) {
    return switch (iconStyle) {
      ProxiesIconStyle.filled => SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: context.raisedSurfaceLevel.colorOf(context.colorScheme),
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(
                  AppCorner.xl.ap(context) - _brandIconTileShrink,
                ),
              ),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(_brandIconTilePadding.ap(context)),
            child: GroupBrandIcon(
              src: src,
              name: name,
              size: size - _brandIconTileShrink.ap(context),
            ),
          ),
        ),
      ),
      ProxiesIconStyle.plain => GroupBrandIcon(
        src: src,
        name: name,
        size: size,
      ),
      ProxiesIconStyle.hidden => const SizedBox.shrink(),
    };
  }
}

/// The type word and the share of members with a live delay, as zashboard
/// counts them: a member counts when its latest recorded delay is above
/// zero, against the group's full size.
class _GroupAvailability extends ConsumerWidget {
  const _GroupAvailability({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delayMap = ref.watch(delayDataSourceProvider);
    final groups = ref.watch(groupsProvider);
    final selectedMap = ref.watch(selectedMapProvider);
    final defaultTestUrl = ref.watch(realTestUrlProvider());
    final available = countAvailableProxies(
      group: group,
      groups: groups,
      selectedMap: selectedMap,
      delayMap: delayMap,
      defaultTestUrl: defaultTestUrl,
    );
    final total = groups.getGroup(group.name)?.all.length ?? group.all.length;
    return Text(
      '${group.type.displayName.toUpperCase()} · $available/$total',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyle.caption1.of(context).toLight,
    );
  }
}

/// The pill sits at the row's end, its right edge on the brand icon's; the
/// trailing inset matches the filled tile's padding, none otherwise.
class _GroupBottomRow extends ConsumerWidget {
  const _GroupBottomRow({
    required this.group,
    required this.cardType,
    required this.iconStyle,
    required this.unfolded,
    required this.onDelayTest,
  });

  final Group group;
  final ProxyCardType cardType;
  final ProxiesIconStyle iconStyle;
  final bool unfolded;
  final VoidCallback onDelayTest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = _cardMetrics(cardType);
    final proxyName = ref
        .watch(selectedProxyNameProvider(group.name))
        .takeFirstValid([]);
    return Row(
      children: [
        Expanded(child: _SelectedProxy(group: group)),
        SizedBox(width: metrics.nameIconGap),
        if (unfolded && proxyName.isNotEmpty) ...[
          _SelectedSpeeds(proxyName: proxyName),
          const SizedBox(width: _nowGap),
        ],
        _SelectedDelay(group: group, onDelayTest: onDelayTest),
        if (iconStyle == ProxiesIconStyle.filled)
          SizedBox(width: _brandIconTilePadding.ap(context)),
      ],
    );
  }
}

String _rateText(num bytes) {
  final show = bytes.traffic;
  return '${show.value} ${show.unit}/s';
}

class _SelectedSpeeds extends ConsumerWidget {
  const _SelectedSpeeds({required this.proxyName});

  final String proxyName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(isStartProvider);
    final speed = ref.watch(
      nodeSpeedsProvider.select(
        (speeds) => speeds[proxyName] ?? const Traffic(),
      ),
    );
    final shown = running ? speed : const Traffic();
    final style = AppTextStyle.caption2.of(context, emphasized: true).toLight;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: _nowGap,
      children: [
        _SpeedFigure(glyph: AppGlyphs.arrowUp, bytes: shown.up, style: style),
        _SpeedFigure(
          glyph: AppGlyphs.arrowDown,
          bytes: shown.down,
          style: style,
        ),
      ],
    );
  }
}

class _SpeedFigure extends StatelessWidget {
  const _SpeedFigure({
    required this.glyph,
    required this.bytes,
    required this.style,
  });

  final Glyph glyph;
  final num bytes;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        GlyphIcon(glyph, size: 12, color: style.color),
        Text(_rateText(bytes), maxLines: 1, style: style),
      ],
    );
  }
}

/// The selected node, with the arrow before its name and its icon when it
/// has one; a node with neither a group icon nor a brand mark shows no
/// single-character monogram. A load-balance group has no pick, so it shows
/// its state instead.
class _SelectedProxy extends ConsumerWidget {
  const _SelectedProxy({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxyName = ref
        .watch(selectedProxyNameProvider(group.name))
        .takeFirstValid([]);
    final colorScheme = context.colorScheme;
    final muted = colorScheme.onSurfaceVariant;
    if (proxyName.isEmpty) {
      if (group.type != GroupType.LoadBalance) {
        return const SizedBox.shrink();
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlyphIcon(AppGlyphs.checkCircle, size: _nowIconSize, color: muted),
          const SizedBox(width: _nowGap),
          Flexible(
            child: Text(
              context.appLocalizations.loadBalance,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1
                  .of(context, emphasized: true)
                  .toLight,
            ),
          ),
        ],
      );
    }
    final icon = ref.watch(
      groupsProvider.select((groups) => groups.getGroup(proxyName)?.icon ?? ''),
    );
    final hasArtwork = icon.isNotEmpty || brandIconFor(proxyName) != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlyphIcon(AppGlyphs.arrowRightCircle, size: _nowIconSize, color: muted),
        const SizedBox(width: _nowGap),
        if (hasArtwork) ...[
          GroupBrandIcon(src: icon, name: proxyName, size: _nodeIconSize),
          const SizedBox(width: _nowGap),
        ],
        Flexible(
          child: EmojiText(
            proxyName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.caption1.of(context, emphasized: true).toLight,
          ),
        ),
      ],
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
                      ? '$delay'
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
