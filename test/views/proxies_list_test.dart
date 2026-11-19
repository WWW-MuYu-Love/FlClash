import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart' hide ListHeader;
import 'package:fl_clash/views/proxies/card.dart';
import 'package:fl_clash/views/proxies/list.dart';
import 'package:fl_clash/views/views.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/glyph_finders.dart';
import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

void main() {
  testWidgets('the list scrolls its rows under the bar, pinning the header '
      'at its foot', (tester) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final profile = Profile.normal().copyWith(
      currentGroupName: 'Selector',
      selectedMap: {'Selector': 'Proxy 1'},
      unfoldSet: {'Selector'},
    );
    final group = Group(
      name: 'Selector',
      type: GroupType.Selector,
      hidden: false,
      now: 'Proxy 1',
      all: List.generate(
        160,
        (index) => Proxy(name: 'Proxy $index', type: 'Direct'),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: [group]),
        ),
        groupsProvider.overrideWithValue([group]),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(500, 1000));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: ProxiesView()),
      ),
    );
    container
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => state.copyWith(type: ProxiesType.list));
    await tester.pump();

    final barBottom = tester.getRect(find.byType(AppBar)).bottom;
    final contentTop = tester
        .element(find.byType(ListHeader))
        .contentTopPadding;
    expect(tester.getRect(find.byType(ListHeader)).top, contentTop);

    await tester.drag(find.byType(ProxyCard).first, const Offset(0, -300));
    await tester.pump();

    expect(tester.getRect(find.byType(ListHeader)).top, contentTop);
    expect(
      find
          .byType(ProxyCard)
          .evaluate()
          .map((element) => tester.getRect(find.byWidget(element.widget))),
      contains(
        predicate<Rect>(
          (rect) => rect.top < barBottom && rect.bottom > 0,
          'a card under the bar',
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('builds only the headers near the view and pins a far one '
      'once its rows reach the bar', (tester) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final profile = Profile.normal().copyWith(unfoldSet: {'Far'});
    final groups = [
      for (var index = 0; index < 40; index++)
        Group(name: 'G$index', type: GroupType.Selector, hidden: false),
      Group(
        name: 'Far',
        type: GroupType.Selector,
        hidden: false,
        all: List.generate(
          160,
          (index) => Proxy(name: 'Proxy $index', type: 'Direct'),
        ),
      ),
    ];
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: groups),
        ),
        groupsProvider.overrideWithValue(groups),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(500, 1000));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: ProxiesView()),
      ),
    );
    container
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => state.copyWith(type: ProxiesType.list));
    await tester.pump();

    expect(
      find.byType(ListHeader, skipOffstage: false).evaluate().length,
      lessThan(groups.length ~/ 2),
    );

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(position.maxScrollExtent - 1000);
    await tester.pump();

    final far = find.ancestor(
      of: find.text('Far'),
      matching: find.byType(ListHeader),
    );
    expect(tester.getRect(far).top, tester.element(far).contentTopPadding);
    expect(find.text('G0', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the folder bar renders the group-tab capsules and filters '
      'the list', (tester) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final profile = Profile.normal();
    const groups = [
      Group(
        name: 'Outer',
        type: GroupType.Selector,
        hidden: false,
        all: [Proxy(name: 'Inner', type: 'Selector')],
      ),
      Group(
        name: 'Inner',
        type: GroupType.Selector,
        hidden: false,
        all: [Proxy(name: 'Proxy 1', type: 'Direct')],
      ),
    ];
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        currentGroupsStateProvider.overrideWithValue(
          const GroupsState(value: groups),
        ),
        groupsProvider.overrideWithValue(groups),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(500, 1000));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: ProxiesView()),
      ),
    );
    container
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => state.copyWith(type: ProxiesType.list));
    await tester.pump();

    Finder folderPillOf(String label) =>
        find.ancestor(of: find.text(label), matching: find.byType(Card));

    for (final label in ['All', 'Strategy', 'Nodes', 'Leaf Nodes']) {
      final pill = tester.widget<Card>(folderPillOf(label));
      expect(pill.fillsSelection, isTrue, reason: label);
      expect(pill.shape, AppShape.full, reason: label);
    }
    expect(tester.widget<Card>(folderPillOf('All')).isSelected, isTrue);
    expect(tester.widget<Card>(folderPillOf('Strategy')).isSelected, isFalse);
    expect(tester.widget<Card>(folderPillOf('Nodes')).isSelected, isFalse);
    expect(tester.widget<Card>(folderPillOf('Leaf Nodes')).isSelected, isFalse);

    expect(
      find.descendant(
        of: folderPillOf('All'),
        matching: find.byGlyph(AppGlyphs.dashboard),
      ),
      findsOneWidget,
    );
    for (final label in ['Strategy', 'Nodes']) {
      expect(
        find.descendant(
          of: folderPillOf(label),
          matching: find.byGlyph(AppGlyphs.folder),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: folderPillOf('Leaf Nodes'),
        matching: find.byGlyph(AppGlyphs.devices),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: folderPillOf('All'), matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: folderPillOf('Strategy'), matching: find.text('1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: folderPillOf('Nodes'), matching: find.text('1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: folderPillOf('Leaf Nodes'), matching: find.text('1')),
      findsNothing,
    );

    await tester.tap(find.text('Nodes'));
    await tester.pump();
    expect(find.text('Outer'), findsNothing);
    expect(find.text('Inner'), findsOneWidget);
    expect(tester.widget<Card>(folderPillOf('Nodes')).isSelected, isTrue);

    await tester.tap(find.text('Leaf Nodes'));
    await tester.pump();
    expect(find.text('Outer'), findsNothing);
    expect(find.text('Inner'), findsNothing);
    expect(find.text('Proxy 1', findRichText: true), findsOneWidget);
    expect(tester.widget<Card>(folderPillOf('Leaf Nodes')).isSelected, isTrue);

    await tester.tap(find.text('All'));
    await tester.pump();
    expect(find.text('Outer'), findsOneWidget);
    expect(find.text('Inner'), findsOneWidget);
    expect(tester.widget<Card>(folderPillOf('All')).isSelected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the bar bolt tests every group in the list style', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final profile = Profile.normal();
    const groups = [
      Group(
        name: 'Outer',
        type: GroupType.Selector,
        hidden: false,
        all: [Proxy(name: 'Inner', type: 'Selector')],
      ),
      Group(
        name: 'Inner',
        type: GroupType.Selector,
        hidden: false,
        all: [Proxy(name: 'Proxy 1', type: 'Direct')],
      ),
    ];
    _RecordingProxiesAction.tested.clear();
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        currentGroupsStateProvider.overrideWithValue(
          const GroupsState(value: groups),
        ),
        groupsProvider.overrideWithValue(groups),
        proxiesActionProvider.overrideWith(_RecordingProxiesAction.new),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(500, 1000));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: ProxiesView()),
      ),
    );
    container
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => state.copyWith(type: ProxiesType.list));
    await tester.pump();

    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byTooltip('Delay test'),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(_RecordingProxiesAction.tested, ['Outer', 'Inner']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pinned top spacer paints an opaque page colour', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final profile = Profile.normal();
    const groups = [
      Group(
        name: 'Inner',
        type: GroupType.Selector,
        hidden: false,
        all: [Proxy(name: 'Proxy 1', type: 'Direct')],
      ),
    ];
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        currentGroupsStateProvider.overrideWithValue(
          const GroupsState(value: groups),
        ),
        groupsProvider.overrideWithValue(groups),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(500, 1000));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: ProxiesView()),
      ),
    );
    container
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => state.copyWith(type: ProxiesType.list));
    await tester.pump();

    final spacer = find.descendant(
      of: find.byType(PinnedHeaderSliver).first,
      matching: find.byType(ColoredBox),
    );
    expect(spacer, findsOneWidget);
    final spacerColor = tester.widget<ColoredBox>(spacer).color;
    expect(
      spacerColor,
      SurfaceLevel.page.colorOf(
        tester.element(find.byType(ProxiesView)).colorScheme,
      ),
    );
    expect(spacerColor.a, 1.0);
    expect(tester.takeException(), isNull);
  });
}

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
