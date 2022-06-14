import 'package:shared_preferences/shared_preferences.dart';

class KeyValueStore {
  SharedPreferences? _prefs;

  SharedPreferences get _preferences {
    if (_prefs == null) {
      throw Exception('You have to call setup() first!');
    }
    return _prefs!;
  }

  Future<void> setup({SharedPreferences? instance}) async {
    _prefs = _prefs ?? instance ?? await SharedPreferences.getInstance();
  }

  Future<bool> putBool(String key, bool value) {
    return _preferences.setBool(key, value);
  }

  bool? getBool(String key) {
    return _preferences.getBool(key);
  }

  Future<bool> remove(String key) {
    return _preferences.remove(key);
  }
}
