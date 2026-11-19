import 'package:ardrive/gallery/explorer/explorer_view_mode.dart';
import 'package:ardrive/utils/key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements KeyValueStore {
  final values = <String, String>{};
  bool throws = false;

  @override
  Future<bool> putString(String key, String value) async {
    if (throws) throw StateError('no storage');
    values[key] = value;
    return true;
  }

  @override
  String? getString(String key) {
    if (throws) throw StateError('no storage');
    return values[key];
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<bool> putBool(String key, bool value) async => true;
  @override
  bool? getBool(String key) => null;
  @override
  Set<String> getKeys() => values.keys.toSet();
}

void main() {
  test('a drive with no saved view is a list', () async {
    expect(await ExplorerViewModeStore(_MemoryStore()).read('d1'),
        ExplorerViewMode.list);
  });

  test('the view is saved per drive', () async {
    final store = ExplorerViewModeStore(_MemoryStore());
    await store.write('photos', ExplorerViewMode.gallery);
    expect(await store.read('photos'), ExplorerViewMode.gallery);
    expect(await store.read('work'), ExplorerViewMode.list);
  });

  test('an unknown saved value is a list', () async {
    final memory = _MemoryStore();
    memory.values[ExplorerViewModeStore.keyFor('d1')] = 'carousel';
    expect(
        await ExplorerViewModeStore(memory).read('d1'), ExplorerViewMode.list);
  });

  test('storage that fails still lets the view switch', () async {
    final memory = _MemoryStore()..throws = true;
    final store = ExplorerViewModeStore(memory);
    await store.write('d1', ExplorerViewMode.gallery);
    expect(await store.read('d1'), ExplorerViewMode.list);
  });
}
