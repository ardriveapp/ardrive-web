import 'dart:async';

abstract class KeyValueStore {
  Future<bool> putBool(String key, bool value);
  FutureOr<bool?> getBool(String key);
  Future<bool> putString(String key, String value);
  FutureOr<String?> getString(String key);
  Future<bool> remove(String key);
  FutureOr<Set<String>> getKeys();
}
