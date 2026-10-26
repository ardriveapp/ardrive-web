import 'package:ardrive/arns/data/arns_pending_action_store.dart';
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

ArNSPendingAction _action(String nonce, {String name = 'blog_acme'}) =>
    ArNSPendingAction(
      nonce: nonce,
      paymentUrl: 'https://payment.example',
      name: name,
      description: 'set-record $name -> tx',
      createdAt: DateTime.utc(2026, 10, 26, 12),
    );

void main() {
  late _MemoryStore memory;
  late ArNSPendingActionStore store;

  setUp(() {
    memory = _MemoryStore()..values['config'] = '{}';
    store = ArNSPendingActionStore(openStore: () async => memory);
  });

  test('keeps each profile its own actions, through a reload', () async {
    await store.add('profile-a', _action('a1'));
    await store.add('profile-a', _action('a2', name: 'acme'));
    await store.add('profile-b', _action('b1'));

    final reloaded = ArNSPendingActionStore(openStore: () async => memory);
    expect(await reloaded.pending('profile-a'),
        [_action('a1'), _action('a2', name: 'acme')]);
    expect(await reloaded.pending('profile-b'), [_action('b1')]);
    expect(await reloaded.pending('profile-c'), isEmpty);
  });

  test('the same nonce twice is one action', () async {
    await store.add('profile', _action('a1'));
    await store.add('profile', _action('a1'));

    expect(await store.pending('profile'), hasLength(1));
  });

  test('forgets an action, and the key with the last one', () async {
    await store.add('profile', _action('a1'));
    await store.add('profile', _action('a2'));

    await store.remove('profile', 'a1');
    expect(await store.pending('profile'), [_action('a2')]);

    await store.remove('profile', 'a2');
    expect(memory.values.keys, ['config']);
  });

  test('sign-out forgets every profile and nothing else', () async {
    await store.add('profile-a', _action('a1'));
    await store.add('profile-b', _action('b1'));

    await store.clear();

    expect(memory.values.keys, ['config']);
  });

  test('a damaged entry reads as nothing pending', () async {
    memory.values['${arnsPendingActionsStoragePrefix}profile'] = 'not json';

    expect(await store.pending('profile'), isEmpty);
  });
}
