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
  late FirstDrive firstDrive;

  setUp(() {
    store = _MemoryStore();
    firstDrive = FirstDrive(openStore: () async => store);
  });

  test('nothing is owed without a request', () async {
    expect(await firstDrive.claim('wallet-a'), isFalse);
  });

  test('a request is owed once, to its own wallet', () async {
    await firstDrive.request('wallet-a');

    expect(await firstDrive.claim('wallet-a'), isTrue);
    expect(await firstDrive.claim('wallet-a'), isFalse);
  });

  test('another wallet spends the request without getting a drive', () async {
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
}
