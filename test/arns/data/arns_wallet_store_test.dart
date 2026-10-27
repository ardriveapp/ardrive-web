import 'package:ardrive/arns/data/arns_wallet_store.dart';
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
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Set<String> getKeys() => values.keys.toSet();

  @override
  Future<bool> putBool(String key, bool value) async => true;

  @override
  bool? getBool(String key) => null;
}

void main() {
  late _MemoryStore memory;
  late ArNSWalletStore store;

  setUp(() {
    memory = _MemoryStore()..values['config'] = '{}';
    store = ArNSWalletStore(openStore: () async => memory);
  });

  test('remembers the linked wallet per profile', () async {
    const phantom = LinkedArNSWallet(address: 'sol-a', walletName: 'Phantom');
    await store.link('profile-1', phantom);
    await store.link('profile-2', const LinkedArNSWallet(address: 'sol-b'));

    expect(await store.linked('profile-1'), phantom);
    expect(
      await store.linked('profile-2'),
      const LinkedArNSWallet(address: 'sol-b'),
    );
    expect(await store.linked('profile-3'), isNull);
  });

  test('unlink forgets one profile', () async {
    await store.link('profile-1', const LinkedArNSWallet(address: 'sol-a'));
    await store.link('profile-2', const LinkedArNSWallet(address: 'sol-b'));

    await store.unlink('profile-1');

    expect(await store.linked('profile-1'), isNull);
    expect(await store.linked('profile-2'), isNotNull);
  });

  test('clear forgets every profile and nothing else', () async {
    await store.link('profile-1', const LinkedArNSWallet(address: 'sol-a'));
    await store.link('profile-2', const LinkedArNSWallet(address: 'sol-b'));

    await store.clear();

    expect(memory.values.keys, ['config']);
  });

  test('a corrupt entry reads as not linked', () async {
    memory.values['${arnsWalletStoragePrefix}profile-1'] = 'not json';

    expect(await store.linked('profile-1'), isNull);
  });
}
