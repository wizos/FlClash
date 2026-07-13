import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'delay_test_scheduler.dart';

const _delayTestConcurrency = 24;
final _delayTestScheduler = DelayTestScheduler<Delay?>(
  maxConcurrent: _delayTestConcurrency,
  runner: _runDelayTest,
);
Future<void> _delayRefreshFuture = Future.value();

double get listHeaderHeight {
  final measure = globalState.measure;
  return 20 + measure.titleMediumHeight + 4 + measure.bodyMediumHeight + 2;
}

double getItemHeight(ProxyCardType proxyCardType) {
  final measure = globalState.measure;
  final baseHeight =
      16 + measure.bodyMediumHeight * 2 + measure.bodySmallHeight + 8 + 4;
  return switch (proxyCardType) {
    ProxyCardType.expand => baseHeight + measure.labelSmallHeight + 6,
    ProxyCardType.shrink => baseHeight,
    ProxyCardType.min => baseHeight - measure.bodyMediumHeight,
  };
}

List<Group> getCurrentGroups() {
  return globalState.container.read(currentGroupsStateProvider).value;
}

List<Group> getGroups() {
  return globalState.container.read(groupsProvider);
}

String? getCurrentGroupName() {
  return globalState.container.read(
    currentProfileProvider.select((state) => state?.currentGroupName),
  );
}

void updateCurrentGroupName(String groupName) {
  globalState.container
      .read(proxiesActionProvider.notifier)
      .updateCurrentGroupName(groupName);
}

void updateCurrentUnfoldSet(Set<String> value) {
  globalState.container
      .read(proxiesActionProvider.notifier)
      .updateCurrentUnfoldSet(value);
}

Future<void> proxyDelayTest(Proxy proxy, [String? testUrl]) {
  return _proxyDelayTest(proxy, testUrl);
}

Future<void> _proxyDelayTest(Proxy proxy, String? testUrl) async {
  final target = _resolveDelayTestTarget(proxy, testUrl);
  if (target == null) return;
  await _delayTestScheduler.schedule(target, priority: true);
  await _enqueueDelayRefresh(() {
    return globalState.container
        .read(proxiesActionProvider.notifier)
        .updateGroupNow();
  });
}

DelayTestTarget? _resolveDelayTestTarget(Proxy proxy, String? testUrl) {
  final ref = globalState.container;
  final groups = getGroups();
  final selectedMap = ref.read(
    currentProfileProvider.select((state) => state?.selectedMap ?? {}),
  );
  final groupNowMap = ref.read(groupNowDataSourceProvider);
  final state = computeRealSelectedProxyState(
    proxy.name,
    groups: groups,
    selectedMap: selectedMap,
    groupNowMap: groupNowMap,
  );
  final currentTestUrl = state.testUrl.takeFirstValid([
    ref.read(realTestUrlProvider(testUrl)),
  ]);
  if (state.proxyName.isEmpty) {
    return null;
  }
  final profile = ref.read(currentProfileProvider);
  return (
    profileId: profile?.id,
    profileUpdatedAt: profile?.lastUpdateDate,
    name: state.proxyName,
    url: currentTestUrl,
  );
}

bool _isCurrentDelayTestTarget(DelayTestTarget target) {
  final profile = globalState.container.read(currentProfileProvider);
  return profile?.id == target.profileId &&
      profile?.lastUpdateDate == target.profileUpdatedAt;
}

Future<Delay?> _runDelayTest(DelayTestTarget target) async {
  if (!_isCurrentDelayTestTarget(target)) return null;
  final ref = globalState.container;
  ref.read(delayTestingTargetsProvider.notifier).start(target);
  try {
    final delay = await coreController.getDelay(target.url, target.name);
    if (_isCurrentDelayTestTarget(target)) {
      ref.read(proxiesActionProvider.notifier).setDelay(delay);
    }
    return delay;
  } catch (_) {
    final delay = Delay(name: target.name, url: target.url, value: -1);
    if (_isCurrentDelayTestTarget(target)) {
      ref.read(proxiesActionProvider.notifier).setDelay(delay);
    }
    return delay;
  } finally {
    ref.read(delayTestingTargetsProvider.notifier).finish(target);
  }
}

Future<void> delayTest(List<Proxy> proxies, [String? testUrl]) async {
  final targets = proxies
      .map((proxy) => _resolveDelayTestTarget(proxy, testUrl))
      .nonNulls
      .toSet()
      .toList();
  if (targets.isEmpty) return;
  final progress = _DelayTestProgress(globalState.container);
  var nextIndex = 0;
  Future<void> worker() async {
    while (nextIndex < targets.length) {
      final target = targets[nextIndex++];
      await _delayTestScheduler.schedule(target);
      await progress.completed();
    }
  }

  final workerCount = targets.length < _delayTestConcurrency
      ? targets.length
      : _delayTestConcurrency;
  await Future.wait(List.generate(workerCount, (_) => worker()));
  await progress.flush();
}

Future<void> _enqueueDelayRefresh(Future<void> Function() refresh) {
  final operation = _delayRefreshFuture.then((_) => refresh());
  _delayRefreshFuture = operation.then<void>((_) {}, onError: (_, _) {});
  return operation;
}

class _DelayTestProgress {
  static const _groupNowThreshold = 10;
  static const _groupsThreshold = 100;
  static const _groupNowInterval = Duration(milliseconds: 350);
  static const _groupsInterval = Duration(seconds: 2);

  final ProviderContainer ref;
  int _groupNowCount = 0;
  int _groupsCount = 0;
  DateTime _lastGroupNowAt = DateTime.now();
  DateTime _lastGroupsAt = DateTime.now();
  Timer? _groupNowTimer;
  Timer? _groupsTimer;

  _DelayTestProgress(this.ref);

  Future<void> completed() async {
    _groupNowCount++;
    _groupsCount++;
    final now = DateTime.now();
    if (_groupsCount >= _groupsThreshold) {
      final elapsed = now.difference(_lastGroupsAt);
      if (elapsed >= _groupsInterval) {
        await _performGroupsRefresh(now);
        return;
      }
      _scheduleGroupsRefresh(_groupsInterval - elapsed);
    }
    if (_groupNowCount >= _groupNowThreshold) {
      final elapsed = now.difference(_lastGroupNowAt);
      if (elapsed >= _groupNowInterval) {
        await _performGroupNowRefresh(now);
      } else {
        _scheduleGroupNowRefresh(_groupNowInterval - elapsed);
      }
    }
  }

  Future<void> flush() {
    _groupNowTimer?.cancel();
    _groupsTimer?.cancel();
    _groupNowCount = 0;
    _groupsCount = 0;
    return _refreshGroups();
  }

  void _scheduleGroupNowRefresh(Duration delay) {
    _groupNowTimer ??= Timer(delay, () {
      _groupNowTimer = null;
      unawaited(_performGroupNowRefresh(DateTime.now()));
    });
  }

  void _scheduleGroupsRefresh(Duration delay) {
    _groupsTimer ??= Timer(delay, () {
      _groupsTimer = null;
      unawaited(_performGroupsRefresh(DateTime.now()));
    });
  }

  Future<void> _performGroupNowRefresh(DateTime now) async {
    _groupNowTimer?.cancel();
    _groupNowTimer = null;
    _groupNowCount = 0;
    _lastGroupNowAt = now;
    await _refreshGroupNow();
  }

  Future<void> _performGroupsRefresh(DateTime now) async {
    _groupNowTimer?.cancel();
    _groupsTimer?.cancel();
    _groupNowTimer = null;
    _groupsTimer = null;
    _groupNowCount = 0;
    _groupsCount = 0;
    _lastGroupNowAt = now;
    _lastGroupsAt = now;
    await _refreshGroups();
  }

  Future<void> _refreshGroupNow() {
    return _enqueueDelayRefresh(
      () => ref.read(proxiesActionProvider.notifier).updateGroupNow(),
    );
  }

  Future<void> _refreshGroups() {
    return _enqueueDelayRefresh(
      () => ref.read(proxiesActionProvider.notifier).updateGroups(),
    );
  }
}

double getScrollToSelectedOffset({
  required String groupName,
  required List<Proxy> proxies,
}) {
  final ref = globalState.container;
  final columns = ref.read(proxiesColumnsProvider);
  final proxyCardType = ref.read(
    proxiesStyleSettingProvider.select((state) => state.cardType),
  );
  final selectedProxyName = ref.read(selectedProxyNameProvider(groupName));
  final findSelectedIndex = proxies.indexWhere(
    (proxy) => proxy.name == selectedProxyName,
  );
  final selectedIndex = findSelectedIndex != -1 ? findSelectedIndex : 0;
  final rows = (selectedIndex / columns).floor();
  return rows * getItemHeight(proxyCardType) + (rows - 1) * 8;
}
