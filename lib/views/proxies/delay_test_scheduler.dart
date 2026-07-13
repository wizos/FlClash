import 'dart:async';
import 'dart:collection';

import 'package:fl_clash/models/models.dart';

typedef DelayTestRunner<T> = Future<T> Function(DelayTestTarget target);

class DelayTestScheduler<T> {
  final int maxConcurrent;
  final DelayTestRunner<T> runner;

  final Queue<_DelayTestEntry<T>> _priorityQueue = Queue();
  final Queue<_DelayTestEntry<T>> _queue = Queue();
  final Map<DelayTestTarget, _DelayTestEntry<T>> _scheduled = {};

  int _activeCount = 0;

  DelayTestScheduler({required this.maxConcurrent, required this.runner})
    : assert(maxConcurrent > 0);

  int get activeCount => _activeCount;

  int get pendingCount => _priorityQueue.length + _queue.length;

  Future<T> schedule(DelayTestTarget target, {bool priority = false}) {
    final scheduled = _scheduled[target];
    if (scheduled != null) {
      if (priority && !scheduled.started && _queue.remove(scheduled)) {
        _priorityQueue.addFirst(scheduled);
      }
      return scheduled.completer.future;
    }

    final completer = Completer<T>();
    final entry = _DelayTestEntry(target: target, completer: completer);
    _scheduled[target] = entry;
    if (priority) {
      _priorityQueue.add(entry);
    } else {
      _queue.add(entry);
    }
    _pump();
    return completer.future;
  }

  void _pump() {
    while (_activeCount < maxConcurrent && pendingCount > 0) {
      final entry = _priorityQueue.isNotEmpty
          ? _priorityQueue.removeFirst()
          : _queue.removeFirst();
      entry.started = true;
      _activeCount++;
      unawaited(_run(entry));
    }
  }

  Future<void> _run(_DelayTestEntry<T> entry) async {
    try {
      entry.completer.complete(await runner(entry.target));
    } catch (error, stackTrace) {
      entry.completer.completeError(error, stackTrace);
    } finally {
      _scheduled.remove(entry.target);
      _activeCount--;
      _pump();
    }
  }
}

class _DelayTestEntry<T> {
  final DelayTestTarget target;
  final Completer<T> completer;
  bool started = false;

  _DelayTestEntry({required this.target, required this.completer});
}
