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

  test('a request older than a day is dropped', () async {
    await firstDrive.request('wallet-a');

    now = now.add(const Duration(days: 1, minutes: 1));

    expect(await firstDrive.claim('wallet-a'), isFalse);
    expect(store.values, isEmpty);
  });
}
