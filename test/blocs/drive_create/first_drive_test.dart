import 'package:ardrive/blocs/drive_create/first_drive.dart';
import 'package:ardrive/utils/key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<bool> putString(String key, String value) async {
    values[key] = value;
    return true;
  }

  @override
  String? getString(String key) => values[key];

  @override
  Future<bool> remove(String key) async => values.remove(key) != null;

  @override
  Set<String> getKeys() => values.keys.toSet();

  @override
  Future<bool> putBool(String key, bool value) async => true;

  @override
  bool? getBool(String key) => null;
}

void main() {
  late _MemoryStore store;
  late DateTime now;
  late FirstDrive firstDrive;

  setUp(() {
    store = _MemoryStore();
    now = DateTime(2026, 10, 29, 12);
    firstDrive = FirstDrive(openStore: () async => store, now: () => now);
  });

  test('nothing is owed without a request', () async {
    expect(await firstDrive.claim('wallet-a'), isFalse);
  });

  test('once made, the request is spent', () async {
    await firstDrive.request('wallet-a');

    expect(await firstDrive.claim('wallet-a'), isTrue);
    await firstDrive.done();
    now = now.add(const Duration(minutes: 5));
    expect(await firstDrive.claim('wallet-a'), isFalse);
  });

  test('another wallet drops the request without getting a drive', () async {
    await firstDrive.request('wallet-a');

    expect(await firstDrive.claim('wallet-b'), isFalse);
    expect(await firstDrive.claim('wallet-a'), isFalse);
  });

  test('two claims at once make one drive', () async {
    await firstDrive.request('wallet-a');

    final claims = await Future.wait(
        [firstDrive.claim('wallet-a'), firstDrive.claim('wallet-a')]);

    expect(claims.where((owed) => owed), hasLength(1));
  });

  test('an attempt that failed for now can be tried again', () async {
    await firstDrive.request('wallet-a');
    expect(await firstDrive.claim('wallet-a'), isTrue);

    await firstDrive.release('wallet-a');

    expect(await firstDrive.claim('wallet-a'), isTrue);
  });

  test('an attempt in progress holds it, until its hold lapses', () async {
    await firstDrive.request('wallet-a');
    expect(await firstDrive.claim('wallet-a'), isTrue);

    // Another tab, a minute later, while the first is still making it.
    now = now.add(const Duration(minutes: 1));
    expect(await firstDrive.claim('wallet-a'), isFalse);

    // The first tab was closed mid-attempt: after the hold, it is retried.
    now = now.add(const Duration(minutes: 2));
    expect(await firstDrive.claim('wallet-a'), isTrue);
  });

  test('asking again leaves a request another tab holds alone', () async {
    await firstDrive.request('w');
    expect(await firstDrive.claim('w'), isTrue);
    final held = store.values.values.single;

    await firstDrive.requestUnlessPending('w');

    expect(store.values.values.single, held);
    expect(await firstDrive.claim('w'), isFalse);
  });

  test('asking again after the request was spent makes it again', () async {
    await firstDrive.request('w');
    await firstDrive.done();

    await firstDrive.requestUnlessPending('w');

    expect(await firstDrive.claim('w'), isTrue);
  });

  group('two tabs', () {
    // Each tab keeps its own copy of the shared storage, as the local store
    // does, and sees the other's writes only when it reads afresh.
    late Map<String, String> shared;
    late Future<void> lockTail;

    Future<T> lock<T>(Future<T> Function() body) {
      final run = lockTail.then((_) => body());
      lockTail = run.then((_) {}, onError: (_) {});
      return run;
    }

    FirstDrive tab({required bool readsAfresh, bool locks = true}) {
      // The copy it took when it opened.
      final cache = _CachedStore(shared)..reload();
      return FirstDrive(
        openStore: () async {
          if (readsAfresh) cache.reload();
          return cache;
        },
        now: () => now,
        exclusive: locks ? lock : <T>(body) => body(),
      );
    }

    setUp(() {
      shared = {};
      lockTail = Future.value();
    });

    test('only one of two tabs claiming at once makes the drive', () async {
      final a = tab(readsAfresh: true);
      final b = tab(readsAfresh: true);
      await a.request('w');

      final claims = await Future.wait([a.claim('w'), b.claim('w')]);

      expect(claims.where((c) => c), hasLength(1));
    });

    test('a tab asking again leaves the other tab\'s hold alone', () async {
      // b opened before anything was asked for.
      final b = tab(readsAfresh: true);
      final a = tab(readsAfresh: true);
      await a.request('w');
      expect(await a.claim('w'), isTrue);
      final held = shared.values.single;

      await b.requestUnlessPending('w');

      expect(shared.values.single, held);
      expect(await b.claim('w'), isFalse);
    });

    test('without a fresh read, a stale tab would claim it too', () async {
      // What the fresh read is for: b's copy predates a's hold.
      final a = tab(readsAfresh: true);
      await a.request('w');
      final b = tab(readsAfresh: false);
      expect(await a.claim('w'), isTrue);

      expect(await b.claim('w'), isTrue);
    });
  });

  test('a request older than a day is dropped', () async {
    await firstDrive.request('wallet-a');

    now = now.add(const Duration(days: 1, minutes: 1));

    expect(await firstDrive.claim('wallet-a'), isFalse);
    expect(store.values, isEmpty);
  });
}

/// A tab's copy of storage shared with other tabs: reads come from the copy,
/// writes go to both, and [reload] refreshes the copy.
class _CachedStore implements KeyValueStore {
  _CachedStore(this.shared);

  final Map<String, String> shared;
  final _copy = <String, String>{};

  void reload() => _copy
    ..clear()
    ..addAll(shared);

  @override
  Future<bool> putString(String key, String value) async {
    _copy[key] = value;
    shared[key] = value;
    return true;
  }

  @override
  String? getString(String key) => _copy[key];

  @override
  Future<bool> remove(String key) async {
    _copy.remove(key);
    return shared.remove(key) != null;
  }

  @override
  Set<String> getKeys() => _copy.keys.toSet();

  @override
  Future<bool> putBool(String key, bool value) async => true;

  @override
  bool? getBool(String key) => null;
}
