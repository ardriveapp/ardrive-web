import 'package:ardrive/services/arweave/transaction_tag_batcher.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<List<String>> queries;
  Set<String> known = {};
  Object? failWith;

  Future<Map<String, Map<String, String>>> fetch(List<String> ids) async {
    queries.add(List.of(ids));
    if (failWith != null) throw failWith!;
    return {
      for (final id in ids)
        if (known.contains(id)) id: {'Cipher': 'c-$id'},
    };
  }

  setUp(() {
    queries = [];
    known = {};
    failWith = null;
  });

  Future<Object?> outcome(Future<Object?> f) =>
      f.then<Object?>((v) => v, onError: (Object e) => e);

  test('concurrent requests go out as one query', () {
    fakeAsync((async) {
      known = {'a', 'b', 'c'};
      final b = TransactionTagBatcher(fetch: fetch);
      final results = <Map<String, String>>[];
      for (final id in ['a', 'b', 'c']) {
        b.tagsFor(id).then(results.add);
      }
      async.elapse(const Duration(milliseconds: 100));
      expect(queries, [
        ['a', 'b', 'c']
      ]);
      expect(results.map((r) => r['Cipher']), ['c-a', 'c-b', 'c-c']);
    });
  });

  test('splits above the cap', () {
    fakeAsync((async) {
      final ids = [for (var i = 0; i < 120; i++) 'tx$i'];
      known = ids.toSet();
      final b = TransactionTagBatcher(fetch: fetch, maxBatch: 50);
      var done = 0;
      for (final id in ids) {
        b.tagsFor(id).then((_) => done++);
      }
      async.elapse(const Duration(milliseconds: 100));
      expect(queries.map((q) => q.length), [50, 50, 20]);
      expect(done, 120);
    });
  });

  test('an answer is cached for the session', () {
    fakeAsync((async) {
      known = {'a'};
      final b = TransactionTagBatcher(fetch: fetch);
      b.tagsFor('a');
      async.elapse(const Duration(milliseconds: 100));
      Map<String, String>? again;
      b.tagsFor('a').then((v) => again = v);
      async.elapse(const Duration(seconds: 5));
      expect(queries.length, 1);
      expect(again!['Cipher'], 'c-a');
    });
  });

  test('the same id asked twice in a window is queried once', () {
    fakeAsync((async) {
      known = {'a'};
      final b = TransactionTagBatcher(fetch: fetch);
      b.tagsFor('a');
      b.tagsFor('a');
      async.elapse(const Duration(milliseconds: 100));
      expect(queries, [
        ['a']
      ]);
    });
  });

  test('an id the gateway has no node for is not found, then cooled down', () {
    fakeAsync((async) {
      known = {'a'};
      final b = TransactionTagBatcher(fetch: fetch);
      Object? missing;
      Object? present;
      outcome(b.tagsFor('gone')).then((v) => missing = v);
      outcome(b.tagsFor('a')).then((v) => present = v);
      async.elapse(const Duration(milliseconds: 100));
      expect(missing, isA<TransactionNotFoundException>());
      expect(present, isA<Map<String, String>>());
      expect(queries.length, 1);

      // Within the cool-down: failed without a query.
      Object? again;
      outcome(b.tagsFor('gone')).then((v) => again = v);
      async.elapse(const Duration(seconds: 30));
      expect(again, isA<TransactionNotFoundException>());
      expect(queries.length, 1);

      // After it: asks once more, and an indexing gap that closed resolves.
      known = {'a', 'gone'};
      Object? later;
      async.elapse(const Duration(seconds: 40));
      outcome(b.tagsFor('gone')).then((v) => later = v);
      async.elapse(const Duration(milliseconds: 100));
      expect(queries.length, 2);
      expect(later, isA<Map<String, String>>());
    });
  });

  test('an error reaches every waiter and is not remembered', () {
    fakeAsync((async) {
      failWith = StateError('network');
      final b = TransactionTagBatcher(fetch: fetch);
      final errors = <Object?>[];
      for (final id in ['a', 'b']) {
        outcome(b.tagsFor(id)).then(errors.add);
      }
      async.elapse(const Duration(milliseconds: 100));
      expect(errors, everyElement(isA<StateError>()));

      failWith = null;
      known = {'a'};
      Object? retry;
      outcome(b.tagsFor('a')).then((v) => retry = v);
      async.elapse(const Duration(milliseconds: 100));
      expect(queries.length, 2);
      expect(retry, isA<Map<String, String>>());
    });
  });

  test('the cool-down follows the clock', () {
    fakeAsync((async) {
      final b = TransactionTagBatcher(fetch: fetch);
      outcome(b.tagsFor('gone'));
      async.elapse(const Duration(milliseconds: 100));
      async.elapse(const Duration(seconds: 61));
      outcome(b.tagsFor('gone'));
      async.elapse(const Duration(milliseconds: 100));
      expect(queries.length, 2);
    });
  });
}
