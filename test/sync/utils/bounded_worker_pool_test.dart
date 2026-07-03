import 'dart:async';

import 'package:ardrive/sync/utils/bounded_worker_pool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('runBoundedWorkers', () {
    test('runs every task exactly once', () async {
      final executed = <int>[];

      await runBoundedWorkers(
        tasks: List.generate(20, (i) => () async => executed.add(i)),
        maxConcurrent: 3,
      );

      expect(executed, hasLength(20));
      expect(executed.toSet(), List.generate(20, (i) => i).toSet());
    });

    test('never exceeds maxConcurrent in-flight tasks', () async {
      const maxConcurrent = 4;
      var inFlight = 0;
      var maxObserved = 0;

      await runBoundedWorkers(
        tasks: List.generate(25, (i) => () async {
          inFlight++;
          if (inFlight > maxObserved) maxObserved = inFlight;
          // Yield a few times so other workers get a chance to overlap.
          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(Duration.zero);
          inFlight--;
        }),
        maxConcurrent: maxConcurrent,
      );

      expect(maxObserved, lessThanOrEqualTo(maxConcurrent));
      expect(maxObserved, greaterThan(1),
          reason: 'tasks should actually overlap');
    });

    test('runs all tasks even when some fail, then reports the first error',
        () async {
      final executed = <int>[];

      Object? caught;
      try {
        await runBoundedWorkers(
          tasks: List.generate(10, (i) => () async {
            executed.add(i);
            if (i == 2) throw StateError('task 2 failed');
          }),
          maxConcurrent: 2,
        );
      } catch (e) {
        caught = e;
      }

      expect(executed, hasLength(10),
          reason: 'a failing task must not stop the remaining tasks');
      expect(caught, isA<StateError>());
    });

    test('handles more workers than tasks', () async {
      var count = 0;

      await runBoundedWorkers(
        tasks: List.generate(2, (_) => () async => count++),
        maxConcurrent: 10,
      );

      expect(count, 2);
    });

    test('completes immediately for an empty task list', () async {
      await expectLater(
        runBoundedWorkers(tasks: [], maxConcurrent: 3),
        completes,
      );
    });

    test('throws ArgumentError for a non-positive maxConcurrent', () {
      expect(
        () => runBoundedWorkers(tasks: [() async {}], maxConcurrent: 0),
        throwsArgumentError,
      );
    });
  });
}
