import 'package:ardrive/utils/key_value_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalKeyValueStore implements KeyValueStore {
  static SharedPreferences? _prefs;

  LocalKeyValueStore._create();

  static Future<KeyValueStore> getInstance({
    /// takes a SharedPreferences for testing purposes
    SharedPreferences? prefs,
  }) async {
    _prefs ??= prefs ?? await SharedPreferences.getInstance();
    return LocalKeyValueStore._create();
  }

  SharedPreferences get _preferences {
    if (_prefs == null) {
      throw Exception('The shared preferences API object is null!');
    }
    return _prefs!;
  }

  @override
  Future<bool> putBool(String key, bool value) {
    return _preferences.setBool(key, value);
  }

  @override
  bool? getBool(String key) {
    return _preferences.getBool(key);
  }

  @override
  Future<bool> putString(String key, String value) {
    return _preferences.setString(key, value);
  }

  @override
  String? getString(String key) {
    return _preferences.getString(key);
  }

  @override
  Future<bool> remove(String key) {
    return _preferences.remove(key);
  }

  @override
  Set<String> getKeys() {
    return _preferences.getKeys();
  }
}
