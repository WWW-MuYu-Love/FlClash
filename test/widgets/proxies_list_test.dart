import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/proxies/card.dart';
import 'package:fl_clash/views/proxies/icon_card.dart';
import 'package:fl_clash/views/proxies/list.dart';
import 'package:fl_clash/widgets/widgets.dart' hide ListHeader;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/glyph_finders.dart';
import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';
import '../helpers/host_scaffold.dart';

const _testUrl = 'https://example.com/generate_204';

class _RecordingProxiesAction extends ProxiesAction {
  static final List<String> tested = [];

  @override
  Future<void> delayTestPageGroup(
    String groupName, {
    bool matchSearch = true,
  }) async {
    tested.add(groupName);
  }
}

Group _group(
  String name,
  int count, {
  String? testUrl,
  GroupType groupType = GroupType.Selector,
  String icon = '',
  List<String>? memberNames,
  Map<String, String> memberIcons = const {},
}) => Group(
  type: groupType,
  name: name,
  icon: icon,
  testUrl: testUrl,
  all: memberNames != null
      ? [
          for (final member in memberNames)
            Proxy(name: member, type: 'ss', icon: memberIcons[member] ?? ''),
        ]
      : [for (var i = 0; i < count; i++) Proxy(name: '$name-$i', type: 'ss')],
);

final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  late ProviderContainer container;

  Future<void> pumpList(
    WidgetTester tester, {
    Map<String, String> selectedMap = const {},
    ViewMode viewMode = ViewMode.mobile,
    List<Group>? groups,
    Set<String> unfoldSet = const {'G0', 'G1', 'G2'},
    ValueListenable<Brightness>? brightness,
    ProxiesType type = ProxiesType.list,
    ProxiesSortType sortType = ProxiesSortType.none,
    ProxyCardType cardType = ProxyCardType.standard,
    ProxiesIconStyle iconStyle = ProxiesIconStyle.filled,
    Locale? locale,
    Map<String, Map<String, int>>? delays,
    Size physicalSize = const Size(900, 700),
  }) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    groups ??= [_group('G0', 40), _group('G1', 30), _group('G2', 60)];
    final profile = Profile.normal().copyWith(
      selectedMap: selectedMap,
      unfoldSet: unfoldSet,
    );
    _RecordingProxiesAction.tested.clear();
    container = ProviderContainer(
      overrides: [
        viewModeProvider.overrideWithValue(viewMode),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: groups),
        ),
        proxiesActionProvider.overrideWith(_RecordingProxiesAction.new),
        proxiesStyleSettingProvider.overrideWithBuild(
          (_, _) => ProxiesStyleProps(
            type: type,
            sortType: sortType,
            cardType: cardType,
            iconStyle: iconStyle,
          ),
        ),
        if (delays != null)
          delayDataSourceProvider.overrideWithBuild((_, _) => delays),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(groupsProvider.notifier).value = groups;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          locale: locale,
          homeBuilder: (child) => HostScaffold(
            body: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(padding: const EdgeInsets.only(top: 64)),
                child: child,
              ),
            ),
          ),
          child: brightness == null
              ? const ProxiesListView()
              : ValueListenableBuilder(
                  valueListenable: brightness,
                  builder: (_, brightness, child) => Theme(
                    data: ThemeData(brightness: brightness),
                    child: child!,
                  ),
                  child: const ProxiesListView(),
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder headerOf(String groupName) => find.ancestor(
    of: find.text(groupName, findRichText: true),
    matching: find.byType(ListHeader),
  );

  Finder actionOf(String groupName, String tooltip) => find.descendant(
    of: headerOf(groupName),
    matching: find.byTooltip(tooltip),
  );

  Finder scrollable() => find
      .descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      )
      .first;

  Future<void> revealHeaderOf(WidgetTester tester, String groupName) async {
    await tester.scrollUntilVisible(
      actionOf(groupName, 'Scroll to selected'),
      200,
      scrollable: scrollable(),
    );
    await tester.pumpAndSettle();
  }

  ShapeDecoration surfaceOf(WidgetTester tester, String groupName) =>
      tester
              .widget<DecoratedBox>(
                find
                    .descendant(
                      of: headerOf(groupName),
                      matching: find.byType(DecoratedBox),
                    )
                    .first,
              )
              .decoration
          as ShapeDecoration;

  testWidgets('scroll to selected lands the row under the pinned header', (
    tester,
  ) async {
    await pumpList(tester, selectedMap: {'G1': 'G1-25'});
    await revealHeaderOf(tester, 'G1');

    await tester.tap(actionOf('G1', 'Scroll to selected'));
    await tester.pumpAndSettle();

    final header = tester.getRect(headerOf('G1'));
    final card = tester.getRect(find.byKey(const ValueKey('G1.G1-25')).first);
    expect(card.top, header.bottom);
  });

  testWidgets('folding a group leaves the cards of the others as they were', (
    tester,
  ) async {
    await pumpList(tester);
    final card = find.byKey(const ValueKey('G0.G0-0')).first;
    final before = tester.widget(card);

    container.read(proxiesActionProvider.notifier).updateCurrentUnfoldSet({
      'G0',
      'G1',
    });
    await tester.pump();

    expect(tester.widget(card), same(before));
  });

  testWidgets('a group unfolds its rows from under its header and folds them '
      'back', (tester) async {
    await pumpList(tester);
    container.read(proxiesActionProvider.notifier).updateCurrentUnfoldSet({
      'G1',
      'G2',
    });
    await tester.pumpAndSettle();
    final radius = AppCorner.xl.ap(tester.element(find.text('G0')));
    final unfolding = find.byType(UnfoldEntryTransition);
    final cards = find.byWidgetPredicate(
      (widget) => widget is ProxyCard && widget.groupName == 'G0',
    );
    BorderRadiusGeometry headerCorners() =>
        (surfaceOf(tester, 'G0').shape as RoundedSuperellipseBorder)
            .borderRadius;

    await tester.tap(find.text('G0'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(unfolding, findsWidgets);
    expect(headerCorners(), AppRadius.all(radius));

    await tester.pumpAndSettle();
    expect(unfolding, findsNothing);
    expect(cards, findsWidgets);
    expect(headerCorners(), AppRadius.vertical(top: radius));

    await tester.tap(find.text('G0'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(unfolding, findsWidgets);
    expect(headerCorners(), AppRadius.all(radius));

    await tester.pumpAndSettle();
    expect(cards, findsNothing);
  });

  testWidgets('the pinned header floats over its rows and leaves with the '
      'bottom of its group card', (tester) async {
    await pumpList(tester);
    expect(surfaceOf(tester, 'G0').shadows, isNull);

    final position = tester.state<ScrollableState>(scrollable()).position;
    position.jumpTo(200);
    await tester.pump();
    final floating = surfaceOf(tester, 'G0');
    expect(floating.shadows, isNotEmpty);
    expect(
      (floating.shape as RoundedSuperellipseBorder).borderRadius,
      AppRadius.all(AppCorner.xl.ap(tester.element(headerOf('G0')))),
    );

    final pinnedTop = tester.getRect(headerOf('G0')).top;
    while (headerOf('G1').evaluate().isEmpty) {
      position.jumpTo(position.pixels + 100);
      await tester.pump();
    }
    final nextTop = tester.getRect(headerOf('G1')).top;
    position.jumpTo(position.pixels + nextTop - pinnedTop - 20);
    await tester.pump();

    expect(
      tester.getRect(headerOf('G0')).bottom,
      tester.getRect(headerOf('G1')).top -
          cardSpacingOf(tester.element(headerOf('G1')), ViewMode.mobile),
    );
    expect(surfaceOf(tester, 'G0').shadows, isNull);
  });

  testWidgets('a folded pinned header takes the page color of a new theme', (
    tester,
  ) async {
    final brightness = ValueNotifier(Brightness.light);
    addTearDown(brightness.dispose);
    await pumpList(tester, unfoldSet: const {}, brightness: brightness);

    brightness.value = Brightness.dark;
    await tester.pumpAndSettle();

    final header = find.ancestor(
      of: headerOf('G0'),
      matching: find.byType(PinnedHeaderSliver),
    );
    final context = tester.element(header);
    final cover = tester.widget<ColoredBox>(
      find.descendant(of: header, matching: find.byType(ColoredBox)).first,
    );
    expect(context.colorScheme.brightness, Brightness.dark);
    expect(cover.color, context.surfaceLevel.colorOf(context.colorScheme));
  });

  testWidgets('the last row sits as far from the bottom of its group card as '
      'from its sides', (tester) async {
    await pumpList(tester);
    final lastCard = find.byWidgetPredicate(
      (widget) => widget is ProxyCard && widget.proxy.name == 'G0-39',
    );
    await tester.scrollUntilVisible(lastCard, 200, scrollable: scrollable());
    await tester.pumpAndSettle();

    final header = tester.getRect(headerOf('G0'));
    final card = tester.getRect(lastCard);
    final nextHeader = tester.getRect(headerOf('G1'));
    final sideInset = header.right - card.right;
    expect(
      nextHeader.top -
          cardSpacingOf(tester.element(headerOf('G1')), ViewMode.mobile) -
          card.bottom,
      sideInset,
    );
  });

  testWidgets('a desktop window lays the groups out in columns and pins the '
      'header of an unfolded one', (tester) async {
    await pumpList(tester, viewMode: ViewMode.desktop);
    container.read(proxiesActionProvider.notifier).updateCurrentUnfoldSet({
      'G2',
    });
    await tester.pumpAndSettle();
    final first = tester.getRect(headerOf('G0'));
    final second = tester.getRect(headerOf('G1'));
    final third = tester.getRect(headerOf('G2'));

    expect(second.top, first.top);
    expect(
      second.left - first.right,
      cardSpacingOf(tester.element(headerOf('G1')), ViewMode.desktop),
    );
    expect(third.left, first.left);
    expect(third.top, greaterThan(first.bottom));

    final position = tester.state<ScrollableState>(scrollable()).position;
    position.jumpTo(40);
    await tester.pump();

    expect(tester.getRect(headerOf('G0')).top, first.top - 40);
    expect(tester.getRect(headerOf('G1')).top, second.top - 40);

    position.jumpTo(third.top - first.top + 200);
    await tester.pump();

    expect(tester.getRect(headerOf('G2')).top, first.top);
  });

  testWidgets('scroll to selected stays put without a selection', (
    tester,
  ) async {
    await pumpList(tester);
    await revealHeaderOf(tester, 'G1');
    final before = tester.getRect(headerOf('G1'));

    await tester.tap(actionOf('G1', 'Scroll to selected'));
    await tester.pumpAndSettle();

    expect(tester.getRect(headerOf('G1')), before);
  });

  testWidgets('a group name too long for its header stays on one line', (
    tester,
  ) async {
    await pumpList(
      tester,
      groups: [_group('Streaming Media Very Long Group Name 流媒体服务分组 ' * 3, 4)],
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('the delay test button tests its own group only', (tester) async {
    await pumpList(tester);

    await tester.tap(actionOf('G0', 'Delay test'));
    await tester.pump();

    expect(_RecordingProxiesAction.tested, ['G0']);
  });

  testWidgets('a group under test spins its button and ignores taps', (
    tester,
  ) async {
    await pumpList(tester);

    container.read(delayTestingGroupsProvider.notifier).start('G0');
    await tester.pump();

    expect(
      find.descendant(
        of: headerOf('G0'),
        matching: find.byType(ActivityIndicator),
      ),
      findsOneWidget,
    );
    await tester.tap(actionOf('G0', 'Delay test'), warnIfMissed: false);
    await tester.pump();
    expect(_RecordingProxiesAction.tested, isEmpty);

    container.read(delayTestingGroupsProvider.notifier).stop('G0');
    await tester.pump();

    expect(find.byType(ActivityIndicator), findsNothing);
  });

  Finder groupCardOf(String groupName) => find.ancestor(
    of: find.text(groupName, findRichText: true),
    matching: find.byType(GroupIconCard),
  );

  int iconTilesOf(WidgetTester tester, Finder card, double size) {
    final boxes = tester.widgetList(
      find.descendant(of: card, matching: find.byType(DecoratedBox)),
    );
    return boxes
        .map((box) => tester.getRect(find.byWidget(box)))
        .where((rect) => rect.width == size && rect.height == size)
        .length;
  }

  testWidgets('the icons style lays the groups out as a two-column '
      'grid', (tester) async {
    await pumpList(tester, type: ProxiesType.icons, unfoldSet: const {});

    final first = tester.getRect(groupCardOf('G0'));
    final second = tester.getRect(groupCardOf('G1'));
    final third = tester.getRect(groupCardOf('G2'));

    expect(second.top, first.top);
    expect(second.left, greaterThan(first.right));
    expect(third.left, first.left);
    expect(third.top, greaterThan(first.bottom));
  });

  testWidgets('a grid card shows the type and the available share', (
    tester,
  ) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      selectedMap: {'G0': 'G0-3'},
      unfoldSet: const {},
    );

    expect(
      find.descendant(
        of: groupCardOf('G0'),
        matching: find.text('SELECTOR · 0/40'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: groupCardOf('G0'),
        matching: find.text('G0-3', findRichText: true),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a grid card shows the built-in brand icon for a known name '
      'and a monogram otherwise', (tester) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      groups: [_group('YouTube', 2), _group('My Nodes', 2)],
      unfoldSet: const {},
    );

    expect(
      find.descendant(
        of: groupCardOf('YouTube'),
        matching: find.byType(SvgPicture),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: groupCardOf('My Nodes'),
        matching: find.byType(GroupMonogram),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a grid card shows the selected node delay as a pill', (
    tester,
  ) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      selectedMap: {'G0': 'G0-0'},
      groups: [_group('G0', 3, testUrl: _testUrl)],
      delays: {
        _testUrl: {'G0-0': 123},
      },
      unfoldSet: const {},
    );

    expect(
      find.descendant(of: groupCardOf('G0'), matching: find.text('123')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: groupCardOf('G0'), matching: find.text('123 ms')),
      findsNothing,
    );
  });

  testWidgets('tapping a grid card folds and unfolds its group', (
    tester,
  ) async {
    await pumpList(tester, type: ProxiesType.icons, unfoldSet: const {});

    final card = find.byWidgetPredicate(
      (widget) =>
          widget is ProxyCard && widget.key == const ValueKey('G0.G0-0'),
    );
    expect(card, findsNothing);

    await tester.tap(find.text('G0', findRichText: true).first);
    await tester.pumpAndSettle();
    expect(card, findsOneWidget);

    await tester.tap(find.text('G0', findRichText: true).first);
    await tester.pumpAndSettle();
    expect(card, findsNothing);
  });

  testWidgets('tapping the delay pill tests its group without folding it', (
    tester,
  ) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      selectedMap: {'G0': 'G0-0'},
      unfoldSet: const {},
    );

    await tester.tap(
      find.descendant(
        of: groupCardOf('G0'),
        matching: find.byGlyph(AppGlyphs.bolt),
      ),
    );
    await tester.pump();

    expect(_RecordingProxiesAction.tested, ['G0']);
    expect(find.byKey(const ValueKey('G0.G0-0')), findsNothing);
  });

  testWidgets('switching the style type swaps the grid cards for list '
      'headers', (tester) async {
    await pumpList(tester, type: ProxiesType.icons);

    expect(find.byType(GroupIconCard), findsWidgets);
    expect(find.byType(ListHeader), findsNothing);

    container
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => state.copyWith(type: ProxiesType.list));
    await tester.pumpAndSettle();

    expect(find.byType(GroupIconCard), findsNothing);
    expect(find.byType(ListHeader), findsWidgets);
  });

  testWidgets('an expanded grid card spans both columns at phone width', (
    tester,
  ) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      groups: [_group('G0', 4), _group('G1', 2), _group('G2', 2)],
      unfoldSet: const {'G0'},
      physicalSize: const Size(390, 844),
    );

    final expanded = tester.getRect(groupCardOf('G0'));
    final first = tester.getRect(groupCardOf('G1'));
    final second = tester.getRect(groupCardOf('G2'));

    expect(expanded.left, moreOrLessEquals(16, epsilon: 1));
    expect(expanded.width, moreOrLessEquals(358, epsilon: 1));
    expect(first.top, greaterThan(expanded.bottom));
    expect(second.top, first.top);
    expect(second.left, greaterThan(first.right));
    expect(first.width, moreOrLessEquals(175, epsilon: 1));
  });

  testWidgets('an expanded grid card shows node names and types in full '
      'at phone width', (tester) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      groups: [
        const Group(
          type: GroupType.Selector,
          name: 'G0',
          all: [
            Proxy(name: '中国自动', type: 'urltest'),
            Proxy(name: '中国手动', type: 'selector'),
            Proxy(name: '美国自动', type: 'fallback'),
            Proxy(name: '日本手动', type: 'hysteria2'),
          ],
        ),
        _group('G1', 2),
      ],
      unfoldSet: const {'G0'},
      physicalSize: const Size(390, 844),
    );

    for (final name in ['中国自动', '中国手动', '美国自动', '日本手动']) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(name, findRichText: true),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
    }
    for (final type in ['urltest', 'selector', 'fallback', 'hysteria2']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(type));
      expect(paragraph.didExceedMaxLines, isFalse);
    }
    final nodeCard = tester.getRect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ProxyCard && widget.key == const ValueKey('G0.中国自动'),
      ),
    );
    expect(nodeCard.width, moreOrLessEquals(165, epsilon: 2));
  });

  testWidgets('collapsing an expanded grid card restores the two-column '
      'grid', (tester) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      groups: [_group('G0', 4), _group('G1', 2), _group('G2', 2)],
      unfoldSet: const {'G0'},
      physicalSize: const Size(390, 844),
    );

    expect(
      tester.getRect(groupCardOf('G0')).width,
      moreOrLessEquals(358, epsilon: 1),
    );

    await tester.tap(find.text('G0', findRichText: true).first);
    await tester.pumpAndSettle();

    final first = tester.getRect(groupCardOf('G0'));
    final second = tester.getRect(groupCardOf('G1'));
    expect(first.width, moreOrLessEquals(175, epsilon: 1));
    expect(second.top, first.top);
    expect(second.left, greaterThan(first.right));
  });

  testWidgets('a grid card counts the available share the way zashboard '
      'does', (tester) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      groups: [
        _group('U', 3, groupType: GroupType.URLTest, testUrl: _testUrl),
        _group('F', 2, groupType: GroupType.Fallback),
        _group('L', 2, groupType: GroupType.LoadBalance),
      ],
      delays: {
        _testUrl: {'U-0': 123, 'U-1': -1},
      },
      unfoldSet: const {},
    );

    expect(find.text('URLTEST · 1/3'), findsOneWidget);
    expect(find.text('FALLBACK · 0/2'), findsOneWidget);
    expect(find.text('LOADBALANCE · 0/2'), findsOneWidget);
  });

  testWidgets('a grid card shows the selected node icon', (tester) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      groups: [
        _group('G0', 3),
        _group('G0-0', 2, icon: 'https://example.com/China.png'),
      ],
      selectedMap: {'G0': 'G0-0'},
      unfoldSet: const {},
    );

    expect(
      find.descendant(
        of: groupCardOf('G0'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is GroupBrandIcon &&
              widget.src == 'https://example.com/China.png' &&
              widget.name == 'G0-0' &&
              widget.size == 16,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a grid card shows the brand icon of a selected node with '
      'no icon of its own', (tester) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      groups: [
        _group('G0', 0, memberNames: ['YouTube', 'x']),
        _group('YouTube', 2),
      ],
      selectedMap: {'G0': 'YouTube'},
      unfoldSet: const {},
    );

    expect(
      find.descendant(of: groupCardOf('G0'), matching: find.byType(SvgPicture)),
      findsOneWidget,
    );
  });

  testWidgets('a grid card shows no monogram for a selected node without '
      'an icon of its own', (tester) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      groups: [_group('G0', 3)],
      selectedMap: {'G0': 'G0-0'},
      unfoldSet: const {},
    );

    final card = groupCardOf('G0');
    expect(
      find.descendant(
        of: card,
        matching: find.text('G0-0', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byType(GroupBrandIcon)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byType(GroupMonogram)),
      findsOneWidget,
    );
  });

  testWidgets('a grid card shows no expand triangle', (tester) async {
    await pumpList(tester, type: ProxiesType.icons, unfoldSet: const {});

    expect(find.byType(ExpandIcon), findsNothing);
  });

  testWidgets('the folder bar shows the group counts', (tester) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      groups: [
        _group('S1', 0, memberNames: ['S2']),
        _group('S2', 0, memberNames: []),
        _group('N1', 0, memberNames: ['x', 'y']),
        _group('N2', 0, memberNames: ['z']),
      ],
      unfoldSet: const {},
    );

    expect(find.text('All'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Strategy'), findsOneWidget);
    expect(find.text('Nodes'), findsOneWidget);
    expect(find.text('2'), findsNWidgets(2));
  });

  testWidgets('sorting by name keeps the grid cards in config order in '
      'icons style', (tester) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      groups: [_group('G2', 2), _group('G0', 2), _group('G1', 2)],
      sortType: ProxiesSortType.name,
      unfoldSet: const {},
    );

    final first = tester.getRect(groupCardOf('G2'));
    final second = tester.getRect(groupCardOf('G0'));
    final third = tester.getRect(groupCardOf('G1'));
    expect(second.top, first.top);
    expect(second.left, greaterThan(first.right));
    expect(third.top, greaterThan(first.bottom));
    expect(third.left, first.left);
  });

  testWidgets('sorting by delay keeps the grid cards in config order in '
      'icons style', (tester) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      groups: [
        _group('G-slow', 2, testUrl: _testUrl),
        _group('G-untested', 2, testUrl: _testUrl),
        _group('G-timeout', 2, testUrl: _testUrl),
        _group('G-fast', 2, testUrl: _testUrl),
      ],
      selectedMap: {
        'G-slow': 'G-slow-0',
        'G-untested': 'G-untested-0',
        'G-timeout': 'G-timeout-0',
        'G-fast': 'G-fast-0',
      },
      delays: {
        _testUrl: {'G-slow-0': 200, 'G-timeout-0': -1, 'G-fast-0': 50},
      },
      sortType: ProxiesSortType.delay,
      unfoldSet: const {},
    );

    final slow = tester.getRect(groupCardOf('G-slow'));
    final untested = tester.getRect(groupCardOf('G-untested'));
    final timeout = tester.getRect(groupCardOf('G-timeout'));
    final fast = tester.getRect(groupCardOf('G-fast'));
    expect(untested.top, slow.top);
    expect(untested.left, greaterThan(slow.right));
    expect(timeout.top, greaterThan(slow.bottom));
    expect(timeout.left, slow.left);
    expect(fast.top, timeout.top);
    expect(fast.left, greaterThan(timeout.right));
  });

  testWidgets('the card size changes the grid card height and brand icon '
      'size in icons style', (tester) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      iconStyle: ProxiesIconStyle.plain,
      unfoldSet: const {},
    );

    Finder brandIcon() => find.descendant(
      of: groupCardOf('G0'),
      matching: find.byWidgetPredicate((widget) => widget is GroupBrandIcon),
    );
    double cardHeight() => tester.getRect(groupCardOf('G0')).height;
    double iconSize() => tester.widget<GroupBrandIcon>(brandIcon()).size;

    final standardHeight = cardHeight();
    expect(iconSize(), 48);

    container
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => state.copyWith(cardType: ProxyCardType.compact));
    await tester.pumpAndSettle();
    expect(cardHeight(), lessThan(standardHeight));
    expect(iconSize(), 40);

    container
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => state.copyWith(cardType: ProxyCardType.loose));
    await tester.pumpAndSettle();
    expect(cardHeight(), greaterThan(standardHeight));
    expect(iconSize(), 56);
  });

  testWidgets('the filled icon style wraps the brand icon in a tile in '
      'icons style', (tester) async {
    await pumpList(tester, type: ProxiesType.icons, unfoldSet: const {});

    expect(iconTilesOf(tester, groupCardOf('G0'), 48), 1);
  });

  testWidgets('the plain icon style shows the bare brand icon in icons '
      'style', (tester) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      iconStyle: ProxiesIconStyle.plain,
      unfoldSet: const {},
    );

    expect(
      find.descendant(
        of: groupCardOf('G0'),
        matching: find.byWidgetPredicate((widget) => widget is GroupBrandIcon),
      ),
      findsOneWidget,
    );
    expect(iconTilesOf(tester, groupCardOf('G0'), 40), 0);
  });

  testWidgets('the hidden icon style hides the group brand icon but keeps '
      'the selected node icon in icons style', (tester) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      iconStyle: ProxiesIconStyle.hidden,
      groups: [
        _group('G0', 3),
        _group('G0-0', 2, icon: 'https://example.com/China.png'),
      ],
      selectedMap: {'G0': 'G0-0'},
      unfoldSet: const {},
    );

    expect(
      find.descendant(
        of: groupCardOf('G0'),
        matching: find.byWidgetPredicate(
          (widget) => widget is GroupBrandIcon && widget.size == 48,
        ),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: groupCardOf('G0'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is GroupBrandIcon &&
              widget.src == 'https://example.com/China.png' &&
              widget.size == 16,
        ),
      ),
      findsOneWidget,
    );

    final hiddenHeight = tester.getRect(groupCardOf('G0')).height;
    container
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => state.copyWith(iconStyle: ProxiesIconStyle.plain));
    await tester.pumpAndSettle();
    expect(tester.getRect(groupCardOf('G0')).height, greaterThan(hiddenHeight));
  });

  testWidgets('tapping a folder tab filters the groups, tapping all '
      'restores them', (tester) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      groups: [
        _group('S1', 0, memberNames: ['S2']),
        _group('S2', 0, memberNames: []),
        _group('N1', 0, memberNames: ['x', 'y']),
        _group('N2', 0, memberNames: ['z']),
      ],
      unfoldSet: const {},
    );

    await tester.tap(find.text('Strategy'));
    await tester.pumpAndSettle();
    expect(find.text('S1', findRichText: true), findsOneWidget);
    expect(find.text('S2', findRichText: true), findsOneWidget);
    expect(find.text('N1', findRichText: true), findsNothing);
    expect(find.text('N2', findRichText: true), findsNothing);

    await tester.tap(find.text('Nodes'));
    await tester.pumpAndSettle();
    expect(find.text('S1', findRichText: true), findsNothing);
    expect(find.text('S2', findRichText: true), findsNothing);
    expect(find.text('N1', findRichText: true), findsOneWidget);
    expect(find.text('N2', findRichText: true), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('S1', findRichText: true), findsOneWidget);
    expect(find.text('S2', findRichText: true), findsOneWidget);
    expect(find.text('N1', findRichText: true), findsOneWidget);
    expect(find.text('N2', findRichText: true), findsOneWidget);
  });

  testWidgets('the node folder flattens every leaf node into a two-column '
      'grid', (tester) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      groups: [
        _group('S1', 0, memberNames: ['S2']),
        _group('S2', 0, memberNames: []),
        _group('N1', 0, memberNames: ['x', 'y']),
        _group('N2', 0, memberNames: ['z', 'x']),
      ],
      unfoldSet: const {},
    );

    await tester.tap(find.text('Leaf Nodes'));
    await tester.pumpAndSettle();
    expect(find.text('S1', findRichText: true), findsNothing);
    expect(find.text('N1', findRichText: true), findsNothing);
    final flatX = find.byWidgetPredicate(
      (widget) => widget is ProxyCard && widget.key == const ValueKey('flat.x'),
    );
    expect(flatX, findsOneWidget);
    expect(tester.widget<ProxyCard>(flatX).groupName, 'N1');
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ProxyCard && widget.key == const ValueKey('flat.y'),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ProxyCard && widget.key == const ValueKey('flat.z'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(flatX, findsNothing);
    expect(find.text('N1', findRichText: true), findsOneWidget);
  });

  testWidgets('a flat node card belongs to the first group holding it', (
    tester,
  ) async {
    await pumpList(
      tester,
      groups: [
        _group('G0', 0, memberNames: ['shared', 'a']),
        _group('G1', 0, memberNames: ['shared', 'b']),
      ],
      selectedMap: {'G1': 'shared'},
      unfoldSet: const {},
    );

    await tester.tap(find.text('Leaf Nodes'));
    await tester.pumpAndSettle();
    final shared = find.byWidgetPredicate(
      (widget) =>
          widget is ProxyCard && widget.key == const ValueKey('flat.shared'),
    );
    expect(shared, findsOneWidget);
    expect(tester.widget<ProxyCard>(shared).groupName, 'G0');
    expect(
      find.descendant(of: shared, matching: find.byType(SelectionBadge)),
      findsNothing,
    );
  });

  testWidgets('the folder pills show every label and count in full at '
      '390dp with 45 groups', (tester) async {
    await pumpList(
      tester,
      locale: const Locale('zh', 'CN'),
      groups: [
        for (var i = 0; i < 30; i++)
          _group('S$i', 0, memberNames: ['N0', 'S$i-1']),
        for (var i = 0; i < 15; i++) _group('N$i', 0, memberNames: ['N$i-0']),
      ],
      unfoldSet: const {},
      physicalSize: const Size(390, 844),
    );

    Finder pillOf(String label) =>
        find.ancestor(of: find.text(label), matching: find.byType(Card));
    for (final (label, width) in [
      ('全部', 24.0),
      ('策略组', 36.0),
      ('节点组', 36.0),
      ('节点', 24.0),
    ]) {
      final textRect = tester.getRect(find.text(label));
      expect(textRect.width, moreOrLessEquals(width, epsilon: 1));
      final pillRect = tester.getRect(pillOf(label));
      expect(pillRect.left, greaterThanOrEqualTo(0));
      expect(pillRect.right, lessThanOrEqualTo(390));
    }
    for (final (label, count) in [
      ('全部', '45'),
      ('策略组', '30'),
      ('节点组', '15'),
      ('节点', '45'),
    ]) {
      expect(
        find.descendant(of: pillOf(label), matching: find.text(count)),
        findsOneWidget,
      );
    }
    final firstLeft = tester.getRect(pillOf('全部')).left;
    final lastRight = tester.getRect(pillOf('节点')).right;
    expect(firstLeft, moreOrLessEquals(11, epsilon: 1));
    expect(390 - lastRight, moreOrLessEquals(firstLeft, epsilon: 1));
  });

  testWidgets('a flat node card paints a visible card fill on the page', (
    tester,
  ) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      locale: const Locale('zh', 'CN'),
      groups: [
        _group('G0', 0, memberNames: ['shared', 'a']),
        _group('G1', 0, memberNames: ['shared', 'b']),
      ],
      unfoldSet: const {},
      physicalSize: const Size(390, 844),
    );

    await tester.tap(find.text('节点'));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(ProxiesListView));
    final colorScheme = context.colorScheme;
    final page = SurfaceLevel.page.colorOf(colorScheme);
    for (final name in ['shared', 'a', 'b']) {
      final card = find.byWidgetPredicate(
        (widget) => widget is ProxyCard && widget.key == ValueKey('flat.$name'),
      );
      expect(card, findsOneWidget);
      final rect = tester.getRect(card);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(844));
      final surface = find.descendant(
        of: card,
        matching: find.byType(PressSurface),
      );
      expect(surface, findsOneWidget);
      final fill = tester.widget<PressSurface>(surface).fill;
      expect(fill, isNot(page));
      expect(fill, SurfaceLevel.card.colorOf(colorScheme));
    }
  });

  testWidgets(
    'a member card shows the member group icon, and none without one',
    (tester) async {
      readRemoteIcon = (_) => Stream.value(_onePixelPng);
      addTearDown(() => readRemoteIcon = null);
      await pumpList(
        tester,
        groups: [
          _group(
            'G0',
            0,
            memberNames: ['中国自动', '台湾01'],
            memberIcons: {'中国自动': 'https://example.com/cn.png'},
          ),
        ],
        unfoldSet: const {'G0'},
      );

      final withIcon = find.byWidgetPredicate(
        (widget) =>
            widget is ProxyCard && widget.key == const ValueKey('G0.中国自动'),
      );
      expect(withIcon, findsOneWidget);
      expect(
        tester
            .widget<GroupBrandIcon>(
              find.descendant(
                of: withIcon,
                matching: find.byType(GroupBrandIcon),
              ),
            )
            .src,
        'https://example.com/cn.png',
      );
      expect(
        find.descendant(of: withIcon, matching: find.byType(Image)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is ProxyCard && widget.key == const ValueKey('G0.台湾01'),
          ),
          matching: find.byType(GroupBrandIcon),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'the collapsed bottom row pins the delay pill to the brand icon',
    (tester) async {
      await pumpList(
        tester,
        type: ProxiesType.icons,
        iconStyle: ProxiesIconStyle.filled,
        physicalSize: const Size(390, 844),
        selectedMap: const {'G0': 'G0-0'},
        groups: [_group('G0', 3, testUrl: _testUrl)],
        delays: {
          _testUrl: {'G0-0': 123},
        },
        unfoldSet: const {},
      );

      final card = groupCardOf('G0');
      final brand = tester.getRect(
        find.descendant(of: card, matching: find.byType(GroupBrandIcon)).first,
      );
      final pill = tester.getRect(
        find.ancestor(
          of: find.descendant(of: card, matching: find.text('123')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is ShapeDecoration &&
                (widget.decoration as ShapeDecoration).shape == AppShape.full,
          ),
        ),
      );
      expect(pill.right, brand.right);
    },
  );

  testWidgets('a long selected name leaves one gap before the delay pill', (
    tester,
  ) async {
    const longName = '中国自动节点名字很长很长很长很长';
    await pumpList(
      tester,
      type: ProxiesType.icons,
      iconStyle: ProxiesIconStyle.filled,
      physicalSize: const Size(390, 844),
      selectedMap: const {'G0': longName},
      groups: [
        _group('G0', 0, memberNames: [longName], testUrl: _testUrl),
      ],
      delays: {
        _testUrl: {longName: 123},
      },
      unfoldSet: const {},
    );

    final card = groupCardOf('G0');
    final name = tester.getRect(
      find.descendant(
        of: card,
        matching: find.text(longName, findRichText: true),
      ),
    );
    final pill = tester.getRect(
      find.ancestor(
        of: find.descendant(of: card, matching: find.text('123')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is ShapeDecoration &&
              (widget.decoration as ShapeDecoration).shape == AppShape.full,
        ),
      ),
    );
    expect(pill.left - name.right, 8);
  });

  testWidgets(
    'an expanded group shows the selected node speeds left of the delay pill',
    (tester) async {
      await pumpList(
        tester,
        type: ProxiesType.icons,
        selectedMap: const {'G0': 'G0-0'},
        groups: [_group('G0', 3, testUrl: _testUrl)],
        delays: {
          _testUrl: {'G0-0': 123},
        },
        unfoldSet: const {'G0'},
      );
      container.read(nodeSpeedsProvider.notifier).setSpeeds({
        'G0-0': const Traffic(up: 1536, down: 2560),
      });
      container.read(runTimeProvider.notifier).value = 60000;
      await tester.pump();

      expect(find.text('1.5 KB/s'), findsOneWidget);
      expect(find.text('2.5 KB/s'), findsOneWidget);
      final card = groupCardOf('G0');
      final up = tester.getRect(find.text('1.5 KB/s'));
      final down = tester.getRect(find.text('2.5 KB/s'));
      final pill = tester.getRect(
        find.ancestor(
          of: find.descendant(of: card, matching: find.text('123')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is ShapeDecoration &&
                (widget.decoration as ShapeDecoration).shape == AppShape.full,
          ),
        ),
      );
      expect(up.right, lessThan(down.left));
      expect(down.right, lessThan(pill.left));
    },
  );

  testWidgets('an expanded bottom row centers the speeds, name and pill', (
    tester,
  ) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      selectedMap: const {'G0': 'G0-0'},
      groups: [_group('G0', 3, testUrl: _testUrl)],
      delays: {
        _testUrl: {'G0-0': 123},
      },
      unfoldSet: const {'G0'},
    );
    container.read(nodeSpeedsProvider.notifier).setSpeeds({
      'G0-0': const Traffic(up: 1536, down: 2560),
    });
    container.read(runTimeProvider.notifier).value = 60000;
    await tester.pump();

    final card = groupCardOf('G0');
    final centers = [
      tester.getRect(find.text('1.5 KB/s')).center.dy,
      tester.getRect(find.text('2.5 KB/s')).center.dy,
      tester
          .getRect(
            find.descendant(
              of: card,
              matching: find.text('G0-0', findRichText: true),
            ),
          )
          .center
          .dy,
      tester
          .getRect(
            find.descendant(
              of: card,
              matching: find.byGlyph(AppGlyphs.arrowRightCircle),
            ),
          )
          .center
          .dy,
      tester
          .getRect(
            find.ancestor(
              of: find.descendant(of: card, matching: find.text('123')),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is DecoratedBox &&
                    widget.decoration is ShapeDecoration &&
                    (widget.decoration as ShapeDecoration).shape ==
                        AppShape.full,
              ),
            ),
          )
          .center
          .dy,
    ];
    for (final center in centers) {
      expect(center, closeTo(centers.first, 1));
    }
  });

  testWidgets('an expanded group with no traffic reads 0 B/s', (tester) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      selectedMap: const {'G0': 'G0-0'},
      groups: [_group('G0', 3, testUrl: _testUrl)],
      delays: {
        _testUrl: {'G0-0': 123},
      },
      unfoldSet: const {'G0'},
    );
    container.read(runTimeProvider.notifier).value = 60000;
    await tester.pump();

    expect(find.text('0 B/s'), findsNWidgets(2));
  });

  testWidgets('speeds read 0 B/s while the tunnel is down', (tester) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      selectedMap: const {'G0': 'G0-0'},
      groups: [_group('G0', 3, testUrl: _testUrl)],
      delays: {
        _testUrl: {'G0-0': 123},
      },
      unfoldSet: const {'G0'},
    );
    container.read(nodeSpeedsProvider.notifier).setSpeeds({
      'G0-0': const Traffic(up: 1536, down: 2560),
    });
    await tester.pump();

    expect(find.text('0 B/s'), findsNWidgets(2));
  });

  testWidgets('a collapsed group shows no speeds', (tester) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      selectedMap: const {'G0': 'G0-0'},
      groups: [_group('G0', 3, testUrl: _testUrl)],
      delays: {
        _testUrl: {'G0-0': 123},
      },
      unfoldSet: const {},
    );
    container.read(nodeSpeedsProvider.notifier).setSpeeds({
      'G0-0': const Traffic(up: 1536, down: 2560),
    });
    container.read(runTimeProvider.notifier).value = 60000;
    await tester.pump();

    expect(find.text('0 B/s'), findsNothing);
    expect(find.text('1.5 KB/s'), findsNothing);
  });

  testWidgets('an expanded group filters its nodes from the magnifier', (
    tester,
  ) async {
    await pumpList(
      tester,
      type: ProxiesType.icons,
      groups: [
        _group('G0', 0, memberNames: ['中国自动', '台湾自动', '香港自动']),
      ],
      unfoldSet: const {'G0'},
    );

    final card = groupCardOf('G0');
    final magnifier = find.descendant(
      of: card,
      matching: find.byGlyph(AppGlyphs.search),
    );
    expect(magnifier, findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(magnifier);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '台湾');
    await tester.pumpAndSettle();
    expect(find.text('台湾自动', findRichText: true), findsOneWidget);
    expect(find.text('中国自动', findRichText: true), findsNothing);
    expect(find.text('香港自动', findRichText: true), findsNothing);

    await tester.enterText(find.byType(TextField), '台湾 手动');
    await tester.pumpAndSettle();
    expect(find.text('台湾自动', findRichText: true), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('中国自动', findRichText: true), findsOneWidget);
    expect(find.text('台湾自动', findRichText: true), findsOneWidget);
    expect(find.text('香港自动', findRichText: true), findsOneWidget);

    await tester.tap(find.byGlyph(Glyphs.clearField));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(magnifier, findsOneWidget);
  });

  testWidgets('a list group filters its nodes from the magnifier', (
    tester,
  ) async {
    await pumpList(
      tester,
      groups: [
        _group('G0', 0, memberNames: ['中国自动', '台湾自动', '香港自动']),
      ],
      unfoldSet: const {'G0'},
    );

    final header = headerOf('G0');
    final magnifier = find.descendant(
      of: header,
      matching: find.byGlyph(AppGlyphs.search),
    );
    expect(magnifier, findsOneWidget);

    await tester.tap(magnifier);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '香港');
    await tester.pumpAndSettle();
    expect(find.text('香港自动', findRichText: true), findsOneWidget);
    expect(find.text('中国自动', findRichText: true), findsNothing);
    expect(find.text('台湾自动', findRichText: true), findsNothing);

    await tester.tap(find.byGlyph(Glyphs.clearField));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('中国自动', findRichText: true), findsOneWidget);
    expect(find.text('台湾自动', findRichText: true), findsOneWidget);
    expect(find.text('香港自动', findRichText: true), findsOneWidget);
  });

  testWidgets('a collapsed group shows no magnifier', (tester) async {
    await pumpList(
      tester,
      groups: [
        _group('G0', 0, memberNames: ['中国自动', '台湾自动']),
      ],
      unfoldSet: const {},
    );

    expect(
      find.descendant(
        of: headerOf('G0'),
        matching: find.byGlyph(AppGlyphs.search),
      ),
      findsNothing,
    );
  });
}
