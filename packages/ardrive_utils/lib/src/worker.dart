import 'dart:async';

import 'package:flutter/foundation.dart';

class Worker<T> {
  final Function(T) onTaskCompleted;
  final Function(T) execute;
  final Function(T, Object e) onError;
  final int maxTasks;
  final T? task;

  List<Future<void>> taskFutures = [];

  Worker({
    required this.onTaskCompleted,
    this.maxTasks = 5,
    required this.execute,
    required this.onError,
    this.task,
  });

  void addTask(T task) {
    if (taskFutures.length < maxTasks) {
      final future = _execute(task);
      taskFutures.add(future);

      future.then((_) {
        taskFutures.remove(future);
        onTaskCompleted(task);
      });
    }
  }

  Future<void> _execute(T task) async {
    try {
      await execute(task);
      return;
    } catch (e) {
      debugPrint('catched error on worker: $e');
      onError(task, e);
    }
  }
}

class WorkerPool<T> {
  final int numWorkers;
  final int maxTasksPerWorker;
  final List<T> taskQueue;
  late List<Worker<T>> workers;
  final Function(T) execute;
  final Function(T) onWorkerError;
  final Completer<void> _completer = Completer<void>();
  int _totalTasks = 0;
  int _completedTasks = 0;

  WorkerPool({
    required this.numWorkers,
    required this.maxTasksPerWorker,
    required this.taskQueue,
    required this.execute,
    required this.onWorkerError,
  }) {
    _totalTasks = taskQueue.length;
    _setWorkerCallbacks();
    _initializeWorkers();
  }

  void _setWorkerCallbacks() {
    workers = List<Worker<T>>.generate(numWorkers, (i) {
      final worker = Worker<T>(
        execute: execute,
        onError: (task, exception) => onWorkerError(task),
        maxTasks: maxTasksPerWorker,
        onTaskCompleted: (task) {
          if (_isCanceled) {
            return;
          }
          _completedTasks++;
          if (_completedTasks == _totalTasks) {
            _completer.complete();
          }
          _assignNextTask(i);
        },
      );
      return worker;
    });
  }

  void _initializeWorkers() {
    for (var i = 0; i < numWorkers; i++) {
      if (kDebugMode) {
        print('Initializing worker with index $i');
      }

      for (var j = 0; j < maxTasksPerWorker; j++) {
        if (kDebugMode) {
          print('Assigning task $j to worker with index $i');
        }
        _assignNextTask(i);
      }
    }
  }

  void _assignNextTask(int workerIndex) {
    if (taskQueue.isNotEmpty) {
      final nextTask = taskQueue.removeAt(0);
      workers[workerIndex].addTask(nextTask);
    }
  }

  void cancel() {
    _isCanceled = true;
    _completer.complete();
  }

  bool get isCanceled => _isCanceled;

  bool _isCanceled = false;

  Future<void> get onAllTasksCompleted => _completer.future;
}
