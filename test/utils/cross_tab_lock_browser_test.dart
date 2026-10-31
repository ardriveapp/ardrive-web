// Web Locks queue requests for one name whoever makes them, so two callers on
// one page wait for each other exactly as two tabs would.
@TestOn('browser')
library;

import 'dart:async';

import 'package:ardrive/utils/cross_tab_lock/cross_tab_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('two bodies under one name run one after the other', () async {
    final events = <String>[];
    final firstMayFinish = Completer<void>();

    final first = runExclusiveAcrossTabs('cross-tab-test', () async {
      events.add('first starts');
      await firstMayFinish.future;
      events.add('first ends');
      return 1;
    });
    final second = runExclusiveAcrossTabs('cross-tab-test', () async {
      events.add('second starts');
      return 2;
    });

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(events, ['first starts']);

    firstMayFinish.complete();
    expect(await first, 1);
    expect(await second, 2);
    expect(events, ['first starts', 'first ends', 'second starts']);
  });

  test('a body that throws hands the error back and frees the lock', () async {
    await expectLater(
      runExclusiveAcrossTabs<int>('cross-tab-test-2', () async {
        throw StateError('storage unavailable');
      }),
      throwsStateError,
    );
    expect(
      await runExclusiveAcrossTabs('cross-tab-test-2', () async => 3),
      3,
    );
  });
}
