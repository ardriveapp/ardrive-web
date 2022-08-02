abstract class KeyValueStore {
  Future<bool> putBool(String key, bool value);
  bool? getBool(String key);
  Future<bool> putString(String key, String value);
  String? getString(String key);
  Future<bool> remove(String key);
  Set<String> getKeys();
}
