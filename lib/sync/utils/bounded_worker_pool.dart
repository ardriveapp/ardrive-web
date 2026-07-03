import 'dart:math';

/// Runs [tasks] with at most [maxConcurrent] executing at any moment.
///
/// Tasks are started in order as workers free up. All tasks run to completion
/// even if some fail, mirroring `Future.wait(..., eagerError: false)`: when
/// one or more tasks throw, the returned future completes with the first
/// error only after every task has finished.
Future<void> runBoundedWorkers({
  required List<Future<void> Function()> tasks,
  required int maxConcurrent,
}) async {
  if (maxConcurrent <= 0) {
    throw ArgumentError.value(
      maxConcurrent,
      'maxConcurrent',
      'must be at least 1',
    );
  }

  if (tasks.isEmpty) {
    return;
  }

  var nextTaskIndex = 0;
  Object? firstError;
  StackTrace? firstStackTrace;

  Future<void> worker() async {
    while (nextTaskIndex < tasks.length) {
      final task = tasks[nextTaskIndex++];
      try {
        await task();
      } catch (e, stackTrace) {
        if (firstError == null) {
          firstError = e;
          firstStackTrace = stackTrace;
        }
      }
    }
  }

  await Future.wait(
    List.generate(min(maxConcurrent, tasks.length), (_) => worker()),
  );

  if (firstError != null) {
    return Future.error(firstError!, firstStackTrace);
  }
}
