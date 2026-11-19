import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

List<Group> computeSort({
  required List<Group> groups,
  required ProxiesSortType sortType,
  required DelayMap delayMap,
  required Map<String, String> selectedMap,
  required String defaultTestUrl,
}) {
  List<Proxy> sortOfDelay({
    required List<Group> groups,
    required List<Proxy> proxies,
    required DelayMap delayMap,
    required Map<String, String> selectedMap,
    required String testUrl,
  }) {
    final delayStates = {
      for (final proxy in proxies)
        proxy.name: computeProxyDelayState(
          proxyName: proxy.name,
          testUrl: testUrl,
          groups: groups,
          selectedMap: selectedMap,
          delayMap: delayMap,
        ),
    };
    return List.of(proxies)
      ..sort((a, b) => delayStates[a.name]!.compareTo(delayStates[b.name]!));
  }

  List<Proxy> sortOfName(List<Proxy> proxies) {
    return List.of(proxies)..sort((a, b) => a.name.compareTo(b.name));
  }

  return groups.map((group) {
    final proxies = group.all;
    final newProxies = switch (sortType) {
      ProxiesSortType.none => proxies,
      ProxiesSortType.delay => sortOfDelay(
        groups: groups,
        proxies: proxies,
        delayMap: delayMap,
        selectedMap: selectedMap,
        testUrl: group.testUrl.takeFirstValid([defaultTestUrl]),
      ),
      ProxiesSortType.name => sortOfName(proxies),
    };
    return group.copyWith(all: newProxies);
  }).toList();
}

/// Sort the groups themselves (the grid's items) by the same rule as nodes:
/// name alphabetically, delay by the group's selected node.
List<Group> sortIconGroups({
  required List<Group> groups,
  required ProxiesSortType sortType,
  required DelayMap delayMap,
  required Map<String, String> selectedMap,
  required String defaultTestUrl,
}) {
  if (sortType == ProxiesSortType.none) return groups;
  if (sortType == ProxiesSortType.name) {
    return List.of(groups)..sort((a, b) => a.name.compareTo(b.name));
  }
  final delayStates = {
    for (final group in groups)
      group.name: _groupDelay(
        group,
        groups: groups,
        delayMap: delayMap,
        selectedMap: selectedMap,
        defaultTestUrl: defaultTestUrl,
      ),
  };
  return List.of(groups)..sort((a, b) {
    final byDelay = delayStates[a.name]!.compareTo(delayStates[b.name]!);
    return byDelay != 0 ? byDelay : a.name.compareTo(b.name);
  });
}

DelayState _groupDelay(
  Group group, {
  required List<Group> groups,
  required DelayMap delayMap,
  required Map<String, String> selectedMap,
  required String defaultTestUrl,
}) {
  final selected = group.getCurrentSelectedName(selectedMap[group.name] ?? '');
  return computeProxyDelayState(
    proxyName: selected,
    testUrl: group.testUrl.takeFirstValid([defaultTestUrl]),
    groups: groups,
    selectedMap: selectedMap,
    delayMap: delayMap,
  );
}

/// Built-in adapters whose delay probe always fails, so a timeout says nothing.
const _unprobeableProxyTypes = {
  'Reject',
  'RejectDrop',
  'Pass',
  'PassRule',
  'Rematch',
  'Compatible',
  'Dns',
};

List<Group> computeHideTimeout({
  required List<Group> groups,
  required List<Group> allGroups,
  required DelayMap delayMap,
  required Map<String, String> selectedMap,
  required String defaultTestUrl,
}) {
  final realStates = <String, SelectedProxyState>{};
  final proxyTypes = {
    for (final group in allGroups)
      for (final proxy in group.all) proxy.name: proxy.type,
  };
  return groups.map((group) {
    final groupTestUrl = group.testUrl.takeFirstValid([defaultTestUrl]);
    final groupWithNow = allGroups.getGroup(group.name) ?? group;
    final selectedName = groupWithNow.getCurrentSelectedName(
      selectedMap[group.name] ?? '',
    );
    final visible = group.all.where((proxy) {
      // A group's delay is its pick's, and hiding it would take away the only
      // way to choose the group where the mode does not show it on its own.
      if (proxy.name == selectedName ||
          allGroups.getGroup(proxy.name) != null) {
        return true;
      }
      final state = realStates.putIfAbsent(
        proxy.name,
        () => computeRealSelectedProxyState(
          proxy.name,
          groups: allGroups,
          selectedMap: selectedMap,
        ),
      );
      if (_unprobeableProxyTypes.contains(proxyTypes[state.proxyName])) {
        return true;
      }
      final testUrl = state.testUrl.takeFirstValid([groupTestUrl]);
      final delay = delayMap[testUrl]?[state.proxyName];
      return delay == null || delay > 0;
    }).toList();
    return group.copyWith(all: visible.isEmpty ? group.all : visible);
  }).toList();
}

SelectedProxyState getRealSelectedProxyState(
  SelectedProxyState state, {
  required List<Group> groups,
  required Map<String, String> selectedMap,
}) {
  if (state.proxyName.isEmpty) return state;
  final group = groups.getGroup(state.proxyName);
  final newState = state.copyWith(group: true);
  if (group == null) return newState;
  final currentSelectedName = group.getCurrentSelectedName(
    selectedMap[newState.proxyName] ?? '',
  );
  if (currentSelectedName.isEmpty) {
    return newState;
  }
  return getRealSelectedProxyState(
    newState.copyWith(proxyName: currentSelectedName, testUrl: group.testUrl),
    groups: groups,
    selectedMap: selectedMap,
  );
}

SelectedProxyState computeRealSelectedProxyState(
  String proxyName, {
  required List<Group> groups,
  required Map<String, String> selectedMap,
}) {
  return getRealSelectedProxyState(
    SelectedProxyState(proxyName: proxyName),
    groups: groups,
    selectedMap: selectedMap,
  );
}

String delayTestKey(String testUrl, String proxyName) {
  return '$testUrl\u0000$proxyName';
}

DelayState computeProxyDelayState({
  required String proxyName,
  required String testUrl,
  required List<Group> groups,
  required Map<String, String> selectedMap,
  required DelayMap delayMap,
}) {
  final state = computeRealSelectedProxyState(
    proxyName,
    groups: groups,
    selectedMap: selectedMap,
  );
  final currentDelayMap =
      delayMap[state.testUrl.takeFirstValid([testUrl])] ?? {};
  final delay = currentDelayMap[state.proxyName];
  return DelayState(delay: delay ?? 0, group: state.group);
}

/// Zashboard folder rule: a node group holds only plain nodes; an empty
/// group counts as a strategy group because it holds no node at all.
bool groupIsNodeOnly(Group group, Set<String> groupNames) {
  if (group.all.isEmpty) return false;
  return group.all.every((proxy) => !groupNames.contains(proxy.name));
}

List<Group> filterGroupsByFolder(
  List<Group> groups,
  ProxyFolder folder,
  Set<String> groupNames,
) {
  return switch (folder) {
    ProxyFolder.all => groups,
    ProxyFolder.strategy =>
      groups.where((group) => !groupIsNodeOnly(group, groupNames)).toList(),
    ProxyFolder.nodes =>
      groups.where((group) => groupIsNodeOnly(group, groupNames)).toList(),
  };
}

int countAvailableProxies({
  required Group group,
  required List<Group> groups,
  required Map<String, String> selectedMap,
  required DelayMap delayMap,
  required String defaultTestUrl,
}) {
  var available = 0;
  for (final proxy in group.all) {
    final delay = computeProxyDelayState(
      proxyName: proxy.name,
      testUrl: group.testUrl.takeFirstValid([defaultTestUrl]),
      groups: groups,
      selectedMap: selectedMap,
      delayMap: delayMap,
    ).delay;
    if (delay > 0) {
      available++;
    }
  }
  return available;
}
