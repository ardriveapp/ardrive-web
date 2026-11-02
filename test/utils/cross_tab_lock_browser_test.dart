// Web Locks queue requests for one name whoever makes them, so two callers on
// one page wait for each other exactly as two tabs would.
@TestOn('browser')
library;

import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;

import 'package:ardrive/utils/cross_tab_lock/cross_tab_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('two bodies under one name run one after the other', () async {
    final events = <String>[];
    final firstStarted = Completer<void>();
    final firstMayFinish = Completer<void>();

    final first = runExclusiveAcrossTabs('cross-tab-test', () async {
      events.add('first starts');
      firstStarted.complete();
      await firstMayFinish.future;
      events.add('first ends');
      return 1;
    });
    final second = runExclusiveAcrossTabs('cross-tab-test', () async {
      events.add('second starts');
      return 2;
    });

    // No guessed timing: wait until the first body holds the lock and the
    // browser reports the second request queued behind it. The second must
    // not have started while the first still holds the lock.
    await firstStarted.future.timeout(const Duration(seconds: 10));
    await _untilHeldWithOneWaiting('cross-tab-test');
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

/// Polls the browser's lock manager until [name] is held and one request for
/// it is pending.
Future<void> _untilHeldWithOneWaiting(String name) async {
  final locks = js_util.getProperty<Object>(
    js_util.getProperty<Object>(js_util.globalThis, 'navigator'),
    'locks',
  );
  int count(Object snapshot, String list) {
    final entries =
        js_util.getProperty<List<Object?>>(snapshot, list).cast<Object>();
    return entries
        .where((e) => js_util.getProperty<String?>(e, 'name') == name)
        .length;
  }

  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final snapshot = await js_util
        .promiseToFuture<Object>(js_util.callMethod(locks, 'query', []));
    if (count(snapshot, 'held') == 1 && count(snapshot, 'pending') == 1) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('the lock was never held with one request waiting');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
