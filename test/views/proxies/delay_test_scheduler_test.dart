import 'dart:async';

import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/views/proxies/delay_test_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DelayTestTarget target(String name) => (
    profileId: 1,
    profileUpdatedAt: null,
    name: name,
    url: 'https://test.local',
  );

  test('limits concurrent tasks', () async {
    var active = 0;
    var maxActive = 0;
    final blockers = <String, Completer<void>>{};
    final scheduler = DelayTestScheduler<String>(
      maxConcurrent: 2,
      runner: (target) async {
        active++;
        maxActive = active > maxActive ? active : maxActive;
        final blocker = blockers[target.name] = Completer<void>();
        await blocker.future;
        active--;
        return target.name;
      },
    );

    final futures = [
      'a',
      'b',
      'c',
      'd',
    ].map((name) => scheduler.schedule(target(name))).toList();
    await Future<void>.delayed(Duration.zero);

    expect(scheduler.activeCount, 2);
    expect(scheduler.pendingCount, 2);
    blockers['a']!.complete();
    blockers['b']!.complete();
    await Future<void>.delayed(Duration.zero);
    blockers['c']!.complete();
    blockers['d']!.complete();

    await Future.wait(futures);
    expect(maxActive, 2);
  });

  test('shares an in-flight task with the same target', () async {
    var runCount = 0;
    final blocker = Completer<void>();
    final scheduler = DelayTestScheduler<String>(
      maxConcurrent: 1,
      runner: (target) async {
        runCount++;
        await blocker.future;
        return target.name;
      },
    );

    final first = scheduler.schedule(target('a'));
    final second = scheduler.schedule(target('a'));
    expect(identical(first, second), isTrue);
    blocker.complete();

    expect(await first, 'a');
    expect(await second, 'a');
    expect(runCount, 1);
  });

  test('runs priority work before normal pending work', () async {
    final order = <String>[];
    final blockers = <String, Completer<void>>{};
    final scheduler = DelayTestScheduler<String>(
      maxConcurrent: 1,
      runner: (target) async {
        order.add(target.name);
        final blocker = blockers[target.name] = Completer<void>();
        await blocker.future;
        return target.name;
      },
    );

    final first = scheduler.schedule(target('a'));
    final normal = scheduler.schedule(target('b'));
    final priority = scheduler.schedule(target('c'), priority: true);
    await Future<void>.delayed(Duration.zero);
    blockers['a']!.complete();
    await Future<void>.delayed(Duration.zero);
    blockers['c']!.complete();
    await Future<void>.delayed(Duration.zero);
    blockers['b']!.complete();

    await Future.wait([first, normal, priority]);
    expect(order, ['a', 'c', 'b']);
  });
}
