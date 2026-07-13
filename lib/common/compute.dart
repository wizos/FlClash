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
    required Map<String, Group> groupByName,
  }) {
    final delayStateByProxyName = {
      for (final proxy in proxies)
        proxy.name: computeProxyDelayState(
          proxyName: proxy.name,
          testUrl: testUrl,
          groups: groups,
          selectedMap: selectedMap,
          delayMap: delayMap,
          groupByName: groupByName,
        ),
    };
    return List.from(proxies)..sort((a, b) {
      final aDelayState = delayStateByProxyName[a.name]!;
      final bDelayState = delayStateByProxyName[b.name]!;
      return aDelayState.compareTo(bDelayState);
    });
  }

  List<Proxy> sortOfName(List<Proxy> proxies) {
    return List.of(proxies)..sort((a, b) => a.name.compareTo(b.name));
  }

  final groupByName = {for (final group in groups) group.name: group};
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
        groupByName: groupByName,
      ),
      ProxiesSortType.name => sortOfName(proxies),
    };
    return group.copyWith(all: newProxies);
  }).toList();
}

SelectedProxyState getRealSelectedProxyState(
  SelectedProxyState state, {
  required List<Group> groups,
  required Map<String, String> selectedMap,
  Map<String, Group>? groupByName,
  Map<String, String> groupNowMap = const {},
  Set<String> visitedGroupNames = const {},
}) {
  if (state.proxyName.isEmpty) return state;
  final newState = state.copyWith(group: true);
  final group =
      groupByName?[state.proxyName] ?? groups.getGroup(state.proxyName);
  if (group == null) return newState;
  if (visitedGroupNames.contains(group.name)) {
    return newState.copyWith(proxyName: '');
  }
  final storedSelectedName = selectedMap[newState.proxyName] ?? '';
  final groupNow = groupNowMap[group.name];
  final currentSelectedName =
      group.type.isComputedSelected && groupNow?.isNotEmpty == true
      ? groupNow!
      : group.getCurrentSelectedName(storedSelectedName);
  if (currentSelectedName.isEmpty) {
    return newState;
  }
  return getRealSelectedProxyState(
    newState.copyWith(proxyName: currentSelectedName, testUrl: group.testUrl),
    groups: groups,
    selectedMap: selectedMap,
    groupByName: groupByName,
    groupNowMap: groupNowMap,
    visitedGroupNames: {...visitedGroupNames, group.name},
  );
}

SelectedProxyState computeRealSelectedProxyState(
  String proxyName, {
  required List<Group> groups,
  required Map<String, String> selectedMap,
  Map<String, Group>? groupByName,
  Map<String, String> groupNowMap = const {},
}) {
  return getRealSelectedProxyState(
    SelectedProxyState(proxyName: proxyName),
    groups: groups,
    selectedMap: selectedMap,
    groupByName: groupByName,
    groupNowMap: groupNowMap,
  );
}

DelayState computeProxyDelayState({
  required String proxyName,
  required String testUrl,
  required List<Group> groups,
  required Map<String, String> selectedMap,
  required DelayMap delayMap,
  Map<String, Group>? groupByName,
  Map<String, String> groupNowMap = const {},
}) {
  final state = computeRealSelectedProxyState(
    proxyName,
    groups: groups,
    selectedMap: selectedMap,
    groupByName: groupByName,
    groupNowMap: groupNowMap,
  );
  final currentDelayMap =
      delayMap[state.testUrl.takeFirstValid([testUrl])] ?? {};
  final delay = currentDelayMap[state.proxyName];
  return DelayState(delay: delay ?? 0, group: state.group);
}
