import 'dart:math';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';
import 'common.dart';
import 'icon_card.dart';

const _headerInset = 10.0;
const _groupInset = 16.0;
const _liftDistance = 16.0;
const _groupMinWidth = 360.0;
const _groupMaxColumns = 3;
const _folderBarHeight = 40.0;
const _folderPillIconGap = 2.0;
const _folderPillCountGap = 1.0;
const _folderPillIconSize = 14.0;
const _flatNodeColumns = 2;
const _lastRowGrowth = _headerInset - proxyGridSpacing;

class ProxiesListView extends ConsumerStatefulWidget {
  const ProxiesListView({super.key});

  @override
  ConsumerState<ProxiesListView> createState() => _ProxiesListViewState();
}

class _ProxiesListViewState extends ConsumerState<ProxiesListView> {
  late final ScrollController _controller;
  int _columns = 1;
  int _groupColumns = 1;
  int _fullColumns = 2;
  bool _iconMode = false;
  double _gap = 0;
  double _headerHeight = 0;
  double _folderBarExtent = 0;
  ProxyFolder _folder = ProxyFolder.all;
  List<Group> _shownGroups = const [];

  /// In-group search keywords by group name, and the groups whose search
  /// field is open. A keyword filters only its own group's nodes.
  final _groupSearchKeywords = <String, String>{};
  final _groupSearchOpen = <String>{};

  String _groupSearchKeyword(String groupName) =>
      _groupSearchKeywords[groupName] ?? '';

  List<Proxy> _visibleProxies(Group group) {
    final keyword = _groupSearchKeyword(group.name);
    if (keyword.isEmpty) {
      return group.all;
    }
    return group.all
        .whereMatches(SearchQuery(keyword), (proxy) => proxy.searchFields)
        .toList();
  }

  void _setGroupSearchKeyword(String groupName, String keyword) {
    setState(() {
      if (keyword.isEmpty) {
        _groupSearchKeywords.remove(groupName);
      } else {
        _groupSearchKeywords[groupName] = keyword;
      }
    });
  }

  void _setGroupSearchOpen(String groupName, bool open) {
    setState(() {
      if (open) {
        _groupSearchOpen.add(groupName);
      } else {
        _groupSearchOpen.remove(groupName);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = sheetScrollController(context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleChange(String groupName) {
    _autoScrollToGroup(groupName);
    final tempUnfoldSet = Set<String>.from(ref.read(unfoldSetProvider));
    if (!tempUnfoldSet.remove(groupName)) {
      tempUnfoldSet.add(groupName);
    }
    ref
        .read(proxiesActionProvider.notifier)
        .updateCurrentUnfoldSet(tempUnfoldSet);
  }

  GroupOffsets _getGroupOffsets() {
    final state = ref.read(proxiesListStateProvider);
    final groups = _shownGroups;
    final offsets = <double>[];
    final rowExtent = getRowExtent(state.proxyCardType);
    if (_iconMode) {
      var cursor = 0.0;
      var index = 0;
      while (index < groups.length) {
        final group = groups[index];
        final start = cursor;
        offsets.add(start);
        cursor += _headerHeight + _gap;
        if (state.currentUnfoldSet.contains(group.name)) {
          final rowCount =
              (_visibleProxies(group).length + _fullColumns - 1) ~/
              _fullColumns;
          cursor += _rowsExtent(rowCount, rowExtent);
          index++;
          continue;
        }
        final next = index + 1 < groups.length ? groups[index + 1] : null;
        if (next != null && !state.currentUnfoldSet.contains(next.name)) {
          offsets.add(start);
          index += 2;
          continue;
        }
        index++;
      }
      return GroupOffsets(groups, offsets);
    }
    final columnOffsets = List.filled(_groupColumns, 0.0);
    for (final (index, group) in groups.indexed) {
      final column = index % _groupColumns;
      offsets.add(columnOffsets[column]);
      columnOffsets[column] += _headerHeight + _gap;
      if (state.currentUnfoldSet.contains(group.name)) {
        final rowCount =
            (_visibleProxies(group).length + _columns - 1) ~/ _columns;
        columnOffsets[column] += _rowsExtent(rowCount, rowExtent);
      }
    }
    return GroupOffsets(groups, offsets);
  }

  double _getGroupOffset(String groupName) {
    if (!_controller.hasClients || _controller.position.maxScrollExtent == 0) {
      return 0;
    }
    return _getGroupOffsets().offsetOf(groupName);
  }

  void _scrollToMakeVisibleWithPadding({
    required double containerHeight,
    required double pixels,
    required double start,
    required double end,
    double padding = 24,
  }) {
    final visibleStart = pixels;
    final visibleEnd = pixels + containerHeight;

    final isElementVisible = start >= visibleStart && end <= visibleEnd;
    if (isElementVisible) {
      return;
    }

    double targetScrollOffset;

    if (end <= visibleStart) {
      targetScrollOffset = start;
    } else if (start >= visibleEnd) {
      targetScrollOffset = end - containerHeight + padding;
    } else {
      final visibleTopPart = end - visibleStart;
      final visibleBottomPart = visibleEnd - start;
      if (visibleTopPart.abs() >= visibleBottomPart.abs()) {
        targetScrollOffset = end - containerHeight + padding;
      } else {
        targetScrollOffset = start;
      }
    }

    targetScrollOffset = targetScrollOffset.clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    );

    _controller.jumpTo(targetScrollOffset);
  }

  void _autoScrollToGroup(String groupName) {
    final pixels = _controller.position.pixels;
    final offset = _getGroupOffset(groupName);
    _scrollToMakeVisibleWithPadding(
      containerHeight: max(
        _controller.position.viewportDimension -
            context.contentTopPadding -
            _folderBarExtent,
        0,
      ),
      pixels: pixels,
      start: offset,
      end: offset + _headerHeight,
    );
  }

  void _scrollToGroupSelected(String groupName) {
    final cardType = ref.read(proxiesListStateProvider).proxyCardType;
    final group = ref.read(proxiesListStateProvider).groups.getGroup(groupName);
    if (group == null) {
      return;
    }
    final proxies = _visibleProxies(group);
    final isExpanded = ref
        .read(proxiesListStateProvider)
        .currentUnfoldSet
        .contains(groupName);
    final rowOffset = selectedRowOffset(
      proxies: proxies,
      selectedProxyName: ref.read(selectedProxyNameProvider(groupName)),
      columns: _iconMode && isExpanded ? _fullColumns : _columns,
      rowExtent: getRowExtent(cardType),
    );
    if (rowOffset == null) {
      return;
    }
    animateScrollTo(_controller, _getGroupOffset(groupName) + rowOffset);
  }

  Widget _buildFlatNodeRows(
    List<({Proxy proxy, Group group})> entries,
    ProxyCardType cardType,
  ) {
    final rows = entries.chunks(_flatNodeColumns).toList();
    return SliverFixedExtentList(
      itemExtent: getRowExtent(cardType),
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildFlatNodeRow(rows[index], cardType),
        childCount: rows.length,
        addAutomaticKeepAlives: false,
      ),
    );
  }

  Widget _buildFlatNodeRow(
    List<({Proxy proxy, Group group})> entries,
    ProxyCardType cardType,
  ) {
    final children = entries
        .map<Widget>(
          (entry) => Flexible(
            child: SizedBox(
              height: getItemHeight(cardType),
              child: ProxyCard(
                testUrl: entry.group.testUrl,
                type: cardType,
                groupType: entry.group.type,
                key: ValueKey('flat.${entry.proxy.name}'),
                proxy: entry.proxy,
                groupName: entry.group.name,
              ),
            ),
          ),
        )
        .fill(
          _flatNodeColumns,
          filler: (_) => const Flexible(child: SizedBox()),
        )
        .separated(const SizedBox(width: 8));
    // No SurfaceScope here: the cards sit on the page, so their fill is one
    // level above it (surfaceBright), a visible white card on the page.
    // Scoping them a level up, like the rows inside an expanded group, would
    // fill them with the page colour itself and leave flat text.
    return Padding(
      padding: const EdgeInsets.only(
        left: _headerInset,
        right: _headerInset,
        bottom: proxyGridSpacing,
      ),
      child: Row(children: children.toList()),
    );
  }

  List<Widget> _buildIconSegments(
    List<Group> shownGroups,
    Set<String> unfoldSet,
    Widget Function(Group group, int columns) buildGroup,
    int halfColumns,
    int fullColumns,
    double gap,
  ) {
    final slivers = <Widget>[];
    var index = 0;
    while (index < shownGroups.length) {
      final group = shownGroups[index];
      if (unfoldSet.contains(group.name)) {
        slivers.add(buildGroup(group, fullColumns));
        index++;
        continue;
      }
      final next = index + 1 < shownGroups.length
          ? shownGroups[index + 1]
          : null;
      final pair = next != null && !unfoldSet.contains(next.name)
          ? [group, next]
          : [group];
      slivers.add(
        SliverCrossAxisGroup(
          slivers: [
            for (var column = 0; column < 2; column++) ...[
              if (column > 0)
                SliverConstrainedCrossAxis(
                  maxExtent: gap,
                  sliver: const SliverToBoxAdapter(),
                ),
              SliverCrossAxisExpanded(
                flex: 1,
                sliver: column < pair.length
                    ? SliverMainAxisGroup(
                        slivers: [buildGroup(pair[column], halfColumns)],
                      )
                    : const SliverToBoxAdapter(),
              ),
            ],
          ],
        ),
      );
      index += pair.length;
    }
    return slivers;
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return Consumer(
      builder: (_, ref, _) {
        final groups = ref.watch(
          proxiesListStateProvider.select((state) => state.groups),
        );
        final cardType = ref.watch(
          proxiesListStateProvider.select((state) => state.proxyCardType),
        );
        final unfoldSet = ref.watch(
          proxiesListStateProvider.select((state) => state.currentUnfoldSet),
        );
        final allGroups = ref.watch(groupsProvider);
        ref.watch(themeSettingProvider.select((state) => state.textScale));
        final viewMode = ref.watch(viewModeProvider);
        final proxiesLayout = ref.watch(
          proxiesStyleSettingProvider.select((state) => state.layout),
        );
        final iconMode = ref.watch(
          proxiesStyleSettingProvider.select(
            (state) => state.type == ProxiesType.icons,
          ),
        );
        final sortType = ref.watch(
          proxiesStyleSettingProvider.select((state) => state.sortType),
        );
        final iconStyle = ref.watch(
          proxiesStyleSettingProvider.select((state) => state.iconStyle),
        );
        final delayMap = ref.watch(delayDataSourceProvider);
        final selectedMap = ref.watch(selectedMapProvider);
        final defaultTestUrl = ref.watch(realTestUrlProvider());
        final isSearching = ref.watch(
          queryProvider(
            QueryTag.proxies,
          ).select((query) => SearchQuery(query).isNotEmpty),
        );
        final groupNames = {for (final group in allGroups) group.name};
        final flatNodes = _folder == ProxyFolder.leafNodes
            ? flatLeafNodes(
                groups: groups,
                sortType: sortType,
                delayMap: delayMap,
                selectedMap: selectedMap,
                defaultTestUrl: defaultTestUrl,
                groupNames: groupNames,
              )
            : const <({Proxy proxy, Group group})>[];
        return NullStatusSwitcher(
          isEmpty: _folder == ProxyFolder.leafNodes
              ? flatNodes.isEmpty
              : groups.isEmpty,
          isSearching: isSearching,
          nullStatus: NullStatus(
            illustration: NullStatusIllustration.proxies,
            label: appLocalizations.nullTip(appLocalizations.proxies),
          ),
          child: WidthBuilder(
            builder: (_, maxWidth) {
              final gap = cardSpacingOf(context, viewMode);
              final width = max(maxWidth - _groupInset * 2, 0.0);
              final groupColumns = iconMode
                  ? 2
                  : viewMode == ViewMode.mobile
                  ? 1
                  : ((width + gap) / (_groupMinWidth + gap)).floor().clamp(
                      1,
                      _groupMaxColumns,
                    );
              final groupWidth =
                  (width - gap * (groupColumns - 1)) / groupColumns;
              final columns = getProxiesColumns(
                max(groupWidth - _headerInset * 2, 0),
                proxiesLayout,
              );
              final fullColumns = getProxiesColumns(
                max(width - _headerInset * 2, 0),
                proxiesLayout,
              );
              final shownGroups = filterGroupsByFolder(
                groups,
                _folder,
                groupNames,
              );
              _columns = columns;
              _groupColumns = groupColumns;
              _fullColumns = fullColumns;
              _iconMode = iconMode;
              _gap = gap;
              _headerHeight = iconMode
                  ? groupIconCardHeightOf(cardType, iconStyle)
                  : listHeaderHeight;
              _folderBarExtent = _folderBarHeight + gap;
              _shownGroups = shownGroups;
              Widget buildGroup(Group group, int groupColumnsCount) =>
                  _GroupSliver(
                    key: iconMode
                        ? GlobalObjectKey(group.name)
                        : _GroupSliverKey(group.name),
                    group: group,
                    columns: groupColumnsCount,
                    cardType: cardType,
                    gap: gap,
                    iconMode: iconMode,
                    headerHeight: _headerHeight,
                    iconStyle: iconStyle,
                    pinnedAbove: context.contentTopPadding + _folderBarExtent,
                    onChange: _handleChange,
                    onScrollToSelected: _scrollToGroupSelected,
                    searchKeyword: _groupSearchKeyword(group.name),
                    searchOpen: _groupSearchOpen.contains(group.name),
                    onSearchKeyword: _setGroupSearchKeyword,
                    onSearchOpen: _setGroupSearchOpen,
                  );
              final folderCounts = (
                all: allGroups.length,
                strategy: allGroups
                    .where((group) => !groupIsNodeOnly(group, groupNames))
                    .length,
                nodes: allGroups
                    .where((group) => groupIsNodeOnly(group, groupNames))
                    .length,
                leafNodes: countLeafNodes(
                  groups: allGroups,
                  groupNames: groupNames,
                ),
              );
              return Scrollbar(
                controller: _controller,
                thumbVisibility: true,
                child: CustomScrollView(
                  key: proxiesListStoreKey,
                  controller: _controller,
                  slivers: [
                    PinnedHeaderSliver(
                      child: ColoredBox(
                        color: SurfaceLevel.page.colorOf(context.colorScheme),
                        child: SizedBox(height: context.contentTopPadding),
                      ),
                    ),
                    PinnedHeaderSliver(
                      child: SizedBox(
                        height: _folderBarExtent,
                        child: _FolderBar(
                          folder: _folder,
                          counts: folderCounts,
                          onChange: (folder) =>
                              setState(() => _folder = folder),
                        ),
                      ),
                    ),
                    if (_folder == ProxyFolder.leafNodes)
                      _buildFlatNodeRows(flatNodes, cardType)
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: _groupInset,
                        ),
                        sliver: iconMode
                            ? SliverMainAxisGroup(
                                slivers: _buildIconSegments(
                                  shownGroups,
                                  unfoldSet,
                                  buildGroup,
                                  columns,
                                  fullColumns,
                                  gap,
                                ),
                              )
                            : groupColumns == 1
                            ? SliverMainAxisGroup(
                                slivers: shownGroups
                                    .map((group) => buildGroup(group, columns))
                                    .toList(),
                              )
                            : SliverCrossAxisGroup(
                                slivers: [
                                  for (
                                    var column = 0;
                                    column < groupColumns;
                                    column++
                                  ) ...[
                                    if (column > 0)
                                      SliverConstrainedCrossAxis(
                                        maxExtent: gap,
                                        sliver: const SliverToBoxAdapter(),
                                      ),
                                    SliverCrossAxisExpanded(
                                      flex: 1,
                                      sliver: SliverMainAxisGroup(
                                        slivers: [
                                          for (
                                            var index = column;
                                            index < shownGroups.length;
                                            index += groupColumns
                                          )
                                            buildGroup(
                                              shownGroups[index],
                                              columns,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                    SliverToBoxAdapter(
                      child: SizedBox(height: 16 + context.bottomInset),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

double _rowsExtent(int rowCount, double rowExtent) =>
    rowCount == 0 ? 0 : rowCount * rowExtent + _lastRowGrowth;

class _GroupSliverKey extends ValueKey<String> {
  const _GroupSliverKey(super.value);
}

/// Watches only its own group's fold state, so folding one group leaves the
/// cards of every other group untouched, and keeps its rows sliver while the
/// inputs that shape it are equal.
class _GroupSliver extends ConsumerStatefulWidget {
  const _GroupSliver({
    super.key,
    required this.group,
    required this.columns,
    required this.cardType,
    required this.gap,
    required this.iconMode,
    required this.headerHeight,
    required this.iconStyle,
    required this.pinnedAbove,
    required this.onChange,
    required this.onScrollToSelected,
    required this.searchKeyword,
    required this.searchOpen,
    required this.onSearchKeyword,
    required this.onSearchOpen,
  });

  final Group group;
  final int columns;
  final ProxyCardType cardType;
  final double gap;

  /// Whether the header is a grid card instead of the list header.
  final bool iconMode;

  final double headerHeight;

  final ProxiesIconStyle iconStyle;

  /// The pinned extent above this group; the header's cover stops there,
  /// because the opaque folder bar already hides the rows above it.
  final double pinnedAbove;

  final void Function(String groupName) onChange;
  final void Function(String groupName) onScrollToSelected;

  /// The in-group search keyword, the field's open state, and their
  /// callbacks. The keyword filters only this group's nodes.
  final String searchKeyword;
  final bool searchOpen;
  final void Function(String groupName, String keyword) onSearchKeyword;
  final void Function(String groupName, bool open) onSearchOpen;

  @override
  ConsumerState<_GroupSliver> createState() => _GroupSliverState();
}

class _GroupSliverState extends ConsumerState<_GroupSliver>
    with SingleTickerProviderStateMixin {
  Widget? _rows;
  double _rowExtent = 0;
  late final _controller = AnimationController(
    vsync: this,
    value: ref.read(unfoldSetProvider).contains(widget.group.name) ? 1 : 0,
  );
  late final _unfold = UnfoldEntryTransition.curveOf(_controller);

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((_) => setState(() {}));
    ref.listenManual(
      unfoldSetProvider.select((state) => state.contains(widget.group.name)),
      (_, isExpand) => _handleUnfold(isExpand),
    );
  }

  @override
  void dispose() {
    _unfold.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleUnfold(bool isExpand) {
    _controller.duration = context.motionDuration(
      UnfoldEntryTransition.duration,
    );
    isExpand ? _controller.forward() : _controller.reverse();
  }

  @override
  void didUpdateWidget(_GroupSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.group != oldWidget.group ||
        widget.columns != oldWidget.columns ||
        widget.cardType != oldWidget.cardType ||
        widget.iconMode != oldWidget.iconMode ||
        widget.headerHeight != oldWidget.headerHeight ||
        widget.searchKeyword != oldWidget.searchKeyword) {
      _rows = null;
    }
  }

  List<Proxy> get _visibleProxies {
    final keyword = widget.searchKeyword;
    if (keyword.isEmpty) {
      return widget.group.all;
    }
    return widget.group.all
        .whereMatches(SearchQuery(keyword), (proxy) => proxy.searchFields)
        .toList();
  }

  Widget _buildRow(BuildContext context, List<Proxy> proxies) {
    final group = widget.group;
    final cardType = widget.cardType;
    final groupName = group.name;
    final children = proxies
        .map<Widget>(
          (proxy) => Flexible(
            child: SizedBox(
              height: getItemHeight(cardType),
              child: ProxyCard(
                testUrl: group.testUrl,
                type: cardType,
                groupType: group.type,
                key: ValueKey('$groupName.${proxy.name}'),
                proxy: proxy,
                groupName: groupName,
              ),
            ),
          ),
        )
        .fill(widget.columns, filler: (_) => const Flexible(child: SizedBox()))
        .separated(const SizedBox(width: 8));
    return SurfaceScope(
      level: context.raisedSurfaceLevel,
      child: Padding(
        padding: const EdgeInsets.only(
          left: _headerInset,
          right: _headerInset,
          bottom: proxyGridSpacing,
        ),
        child: Row(children: children.toList()),
      ),
    );
  }

  Widget _buildRows(double extent) {
    final rows = _visibleProxies.chunks(widget.columns).toList();
    return SliverFixedExtentList(
      itemExtent: extent,
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildRow(context, rows[index]),
        childCount: rows.length,
        addAutomaticKeepAlives: false,
      ),
    );
  }

  /// The card reaches up behind the header's rounded bottom corners, so the
  /// two read as one while the rows unfold or fold.
  Widget _buildUnfoldingRows(double extent, ShapeDecoration decoration) {
    final rows = _visibleProxies.chunks(widget.columns).toList();
    final visible = min(
      rows.length.toDouble(),
      MediaQuery.sizeOf(context).height / extent,
    );
    final count = min(rows.length, visible.floor() + 1);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: -AppCorner.xl.ap(context),
          left: 0,
          right: 0,
          bottom: 0,
          child: DecoratedBox(decoration: decoration),
        ),
        SizeTransition(
          sizeFactor: _unfold,
          alignment: Alignment.topCenter,
          child: Column(
            children: [
              for (var index = 0; index < count; index++)
                UnfoldEntryTransition(
                  animation: _unfold,
                  index: index,
                  visibleCount: visible,
                  child: SizedBox(
                    height: extent,
                    child: _buildRow(context, rows[index]),
                  ),
                ),
              if (count == rows.length) const SizedBox(height: _lastRowGrowth),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupName = widget.group.name;
    final isExpand = ref.watch(
      unfoldSetProvider.select((state) => state.contains(groupName)),
    );
    final unfolded = _controller.isCompleted;
    Widget? rows;
    if (!_controller.isDismissed && _visibleProxies.isNotEmpty) {
      final extent = getRowExtent(widget.cardType);
      final decoration = ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(context.colorScheme),
        shape: AppShape.vertical(
          top: AppCorner.none,
          bottom: AppCorner.xl.ap(context),
        ),
      );
      if (!unfolded) {
        _rows = null;
        rows = SliverToBoxAdapter(
          child: _buildUnfoldingRows(extent, decoration),
        );
      } else {
        if (_rows == null || _rowExtent != extent) {
          _rows = _buildRows(extent);
          _rowExtent = extent;
        }
        rows = DecoratedSliver(
          decoration: decoration,
          sliver: SliverMainAxisGroup(
            slivers: [
              _rows!,
              const SliverToBoxAdapter(child: SizedBox(height: _lastRowGrowth)),
            ],
          ),
        );
      }
    } else {
      _rows = null;
    }
    Widget buildHeader({double floating = 0, double lift = 0}) => SizedBox(
      height: widget.headerHeight,
      child: widget.iconMode
          ? GroupIconCard(
              key: ValueKey(groupName),
              group: widget.group,
              cardType: widget.cardType,
              iconStyle: widget.iconStyle,
              unfolded: unfolded,
              floating: floating,
              lift: lift,
              onChange: () => widget.onChange(groupName),
              onDelayTest: () => ref
                  .read(proxiesActionProvider.notifier)
                  .delayTestPageGroup(groupName),
              searchKeyword: widget.searchKeyword,
              searchOpen: widget.searchOpen,
              onSearchKeyword: (keyword) =>
                  widget.onSearchKeyword(groupName, keyword),
              onSearchOpen: (open) => widget.onSearchOpen(groupName, open),
            )
          : ListHeader(
              enterAnimated: false,
              floating: floating,
              lift: lift,
              onScrollToSelected: widget.onScrollToSelected,
              key: ValueKey(groupName),
              isExpand: isExpand,
              unfolded: unfolded,
              group: widget.group,
              onChange: widget.onChange,
              searchKeyword: widget.searchKeyword,
              searchOpen: widget.searchOpen,
              onSearchKeyword: (keyword) =>
                  widget.onSearchKeyword(groupName, keyword),
              onSearchOpen: (open) => widget.onSearchOpen(groupName, open),
            ),
    );
    return SliverPadding(
      padding: EdgeInsets.only(bottom: widget.gap),
      sliver: SliverMainAxisGroup(
        slivers: [_buildPinnedHeader(isExpand, buildHeader), ?rows],
      ),
    );
  }

  /// Rounds the header and lifts it as its own rows scroll under it, and lets
  /// the shadow go before the end of the group pushes it out. The page color
  /// behind its upper half hides the rows that went under it, which would
  /// otherwise show around its top corners; the pinned bar above hides what
  /// is further up, so the cover stops at the bar. Every header is laid
  /// out on every pass, so one beyond the cache area builds nothing.
  Widget _buildPinnedHeader(
    bool isExpand,
    Widget Function({double floating, double lift}) buildHeader,
  ) {
    final columns = widget.columns;
    final rowCount = (_visibleProxies.length + columns - 1) ~/ columns;
    final rowsExtent = isExpand ? _rowsExtent(rowCount, _rowExtent) : 0.0;
    final groupExtent =
        widget.headerHeight +
        (_controller.isDismissed
            ? 0.0
            : _rowsExtent(rowCount, getRowExtent(widget.cardType)));
    (double, double, double, Color)? headerState;
    Widget? header;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final beyondCache =
            constraints.remainingCacheExtent <= 0 ||
            constraints.scrollOffset + constraints.cacheOrigin >= groupExtent;
        final under = isExpand
            ? constraints.scrollOffset + constraints.overlap
            : 0.0;
        final state = beyondCache
            ? null
            : (
                (under / _liftDistance).clamp(0.0, 1.0),
                (min(under, rowsExtent - under) / _liftDistance).clamp(
                  0.0,
                  1.0,
                ),
                isExpand
                    ? max(0.0, constraints.overlap - widget.pinnedAbove)
                    : 0.0,
                context.surfaceLevel.colorOf(context.colorScheme),
              );
        if (header != null && state == headerState) {
          return header!;
        }
        headerState = state;
        if (state == null) {
          return header = PinnedHeaderSliver(
            child: SizedBox(height: widget.headerHeight),
          );
        }
        final (floating, lift, cover, pageColor) = state;
        return header = PinnedHeaderSliver(
          child: RepaintBoundary(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: -cover,
                  left: 0,
                  right: 0,
                  height: cover + widget.headerHeight / 2,
                  child: ColoredBox(color: pageColor),
                ),
                buildHeader(floating: floating, lift: lift),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ListHeader extends ConsumerWidget {
  final Group group;

  final Function(String groupName) onChange;
  final Function(String groupName) onScrollToSelected;
  final bool isExpand;

  /// Whether the rows have settled under the header, squaring its bottom.
  final bool unfolded;

  final bool enterAnimated;

  /// How far the group's own rows have scrolled under the pinned header, as a
  /// fraction of the distance that rounds its bottom corners.
  final double floating;

  /// The shadow that lifts the header off the rows under it.
  final double lift;

  /// The in-group search keyword, the field's open state, and their
  /// callbacks. The control shows only while the group is open.
  final String searchKeyword;
  final bool searchOpen;
  final ValueChanged<String> onSearchKeyword;
  final ValueChanged<bool> onSearchOpen;

  const ListHeader({
    super.key,
    this.enterAnimated = true,
    this.floating = 0,
    this.lift = 0,
    required this.group,
    required this.onChange,
    required this.onScrollToSelected,
    required this.isExpand,
    required this.unfolded,
    required this.searchKeyword,
    required this.searchOpen,
    required this.onSearchKeyword,
    required this.onSearchOpen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupName = group.name;
    final isDelayTesting = ref.watch(
      delayTestingGroupsProvider.select((state) => state.contains(groupName)),
    );
    final colorScheme = context.colorScheme;
    final level = floating > 0
        ? SurfaceLevel.floatingOf(colorScheme)
        : context.raisedSurfaceLevel;
    final radius = AppCorner.xl.ap(context);
    final card = Card(
      enterActionsOnRight: true,
      enterAnimated: enterAnimated,
      key: key,
      radius: radius - groupHeaderButtonInset,
      child: Padding(
        padding: const EdgeInsets.all(_headerInset - groupHeaderButtonInset),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Row(
                children: [
                  _GroupIcon(src: group.icon, name: groupName),
                  Flexible(child: _GroupSummary(groupName: groupName)),
                ],
              ),
            ),
            _GroupActions(
              isExpand: isExpand,
              isDelayTesting: isDelayTesting,
              groupType: group.type.name,
              onScrollToSelected: () {
                onScrollToSelected(groupName);
              },
              onDelayTest: () {
                ref
                    .read(proxiesActionProvider.notifier)
                    .delayTestPageGroup(groupName);
              },
              onToggle: () {
                onChange(groupName);
              },
              searchKeyword: searchKeyword,
              searchOpen: searchOpen,
              onSearchKeyword: onSearchKeyword,
              onSearchOpen: onSearchOpen,
            ),
          ],
        ),
      ),
      onPressed: () {
        onChange(groupName);
      },
    );
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
          child: card,
        ),
      ),
    );
  }
}

class _GroupIcon extends ConsumerWidget {
  const _GroupIcon({required this.src, required this.name});

  final String src;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconStyle = ref.watch(
      proxiesStyleSettingProvider.select((state) => state.iconStyle),
    );
    return switch (iconStyle) {
      ProxiesIconStyle.filled => LayoutBuilder(
        builder: (_, constraints) {
          return Container(
            margin: const EdgeInsets.only(right: 12),
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                height: constraints.maxHeight,
                width: constraints.maxWidth,
                alignment: Alignment.center,
                padding: EdgeInsets.all(6.ap(context)),
                decoration: ShapeDecoration(
                  color: context.raisedSurfaceLevel.colorOf(
                    context.colorScheme,
                  ),
                  shape: AppShape.all(AppCorner.xl.ap(context) - _headerInset),
                ),
                clipBehavior: Clip.antiAlias,
                child: IconTheme.merge(
                  data: IconThemeData(
                    size: constraints.maxHeight - 12.ap(context),
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                  child: CommonTargetIcon(
                    src: src,
                    fallback: GroupMonogram(name),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      ProxiesIconStyle.plain => Container(
        margin: const EdgeInsets.only(left: 2, right: 10),
        child: LayoutBuilder(
          builder: (_, constraints) {
            return IconTheme.merge(
              data: IconThemeData(
                size: constraints.maxHeight,
                color: context.colorScheme.primary,
              ),
              child: CommonTargetIcon(src: src, fallback: GroupMonogram(name)),
            );
          },
        ),
      ),
      // Lines the title up with the proxy card names below, which sit at the
      // row inset plus the card padding.
      ProxiesIconStyle.hidden => const SizedBox(width: 4),
    };
  }
}

class _GroupSummary extends StatelessWidget {
  const _GroupSummary({required this.groupName});

  final String groupName;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EmojiText(
          groupName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.callout.of(context, emphasized: true),
        ),
        const SizedBox(height: 2),
        Flexible(flex: 1, child: _SelectedProxyName(groupName: groupName)),
      ],
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

class _GroupActions extends StatelessWidget {
  const _GroupActions({
    required this.isExpand,
    required this.isDelayTesting,
    required this.groupType,
    required this.onScrollToSelected,
    required this.onDelayTest,
    required this.onToggle,
    required this.searchKeyword,
    required this.searchOpen,
    required this.onSearchKeyword,
    required this.onSearchOpen,
  });

  final bool isExpand;
  final bool isDelayTesting;
  final String groupType;
  final VoidCallback onScrollToSelected;
  final VoidCallback onDelayTest;
  final VoidCallback onToggle;
  final String searchKeyword;
  final bool searchOpen;
  final ValueChanged<String> onSearchKeyword;
  final ValueChanged<bool> onSearchOpen;

  @override
  Widget build(BuildContext context) {
    return TonalButtonTheme(
      size: TonalButtonSize.compact,
      child: Row(
        children: [
          if (isExpand)
            TonalButtonGroup(
              size: TonalButtonSize.compact,
              children: [
                IconButton(
                  tooltip: context.appLocalizations.scrollToSelected,
                  onPressed: onScrollToSelected,
                  iconSize: 19,
                  icon: const GlyphIcon(AppGlyphs.locate),
                ),
                IconButton(
                  tooltip: context.appLocalizations.delayTest,
                  onPressed: isDelayTesting ? null : onDelayTest,
                  icon: isDelayTesting
                      ? const ActivityIndicator(size: 24)
                      : const GlyphIcon(AppGlyphs.bolt),
                ),
              ],
            )
          else
            Text(
              groupType,
              style: AppTextStyle.caption1
                  .of(context, emphasized: true)
                  .toLight,
            ),
          if (isExpand) ...[
            GroupSearchControl(
              keyword: searchKeyword,
              open: searchOpen,
              onKeyword: onSearchKeyword,
              onOpen: onSearchOpen,
            ),
            const SizedBox(width: 6),
          ] else
            const SizedBox(width: 6),
          ElasticPress(
            child: IconButton(
              tooltip: isExpand
                  ? context.appLocalizations.showLess
                  : context.appLocalizations.showMore,
              onPressed: onToggle,
              icon: ExpandIcon(expand: isExpand),
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderBar extends StatelessWidget {
  const _FolderBar({
    required this.folder,
    required this.counts,
    required this.onChange,
  });

  final ProxyFolder folder;
  final ({int all, int strategy, int nodes, int leafNodes}) counts;
  final ValueChanged<ProxyFolder> onChange;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return ColoredBox(
      color: context.surfaceLevel.colorOf(context.colorScheme),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: _folderBarHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _groupInset),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: Row(
                        children: [
                          Expanded(
                            child: _FolderPill(
                              label: appLocalizations.proxyFolderAll,
                              count: counts.all,
                              glyph: AppGlyphs.dashboard,
                              selected: folder == ProxyFolder.all,
                              onTap: () => onChange(ProxyFolder.all),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _FolderPill(
                              label: appLocalizations.proxyFolderStrategy,
                              count: counts.strategy,
                              glyph: AppGlyphs.folder,
                              selected: folder == ProxyFolder.strategy,
                              onTap: () => onChange(ProxyFolder.strategy),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _FolderPill(
                              label: appLocalizations.proxyFolderNodes,
                              count: counts.nodes,
                              glyph: AppGlyphs.folder,
                              selected: folder == ProxyFolder.nodes,
                              onTap: () => onChange(ProxyFolder.nodes),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _FolderPill(
                              label: appLocalizations.proxyFolderLeafNodes,
                              count: counts.leafNodes,
                              glyph: AppGlyphs.devices,
                              selected: folder == ProxyFolder.leafNodes,
                              onTap: () => onChange(ProxyFolder.leafNodes),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _FolderPill extends StatelessWidget {
  const _FolderPill({
    required this.label,
    required this.count,
    required this.glyph,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Glyph glyph;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Card(
      isSelected: selected,
      fillsSelection: true,
      shape: AppShape.full,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      onPressed: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GlyphIcon(glyph, size: _folderPillIconSize),
          const SizedBox(width: _folderPillIconGap),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1
                  .of(context, emphasized: true)
                  .copyWith(
                    color: selected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(width: _folderPillCountGap),
          Text(
            '$count',
            style: AppTextStyle.caption1
                .of(context)
                .copyWith(
                  color: selected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
