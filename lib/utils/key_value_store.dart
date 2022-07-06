abstract class KeyValueStore {
  Future<bool> putBool(String key, bool value);
  bool? getBool(String key);
  Future<bool> remove(String key);
}
