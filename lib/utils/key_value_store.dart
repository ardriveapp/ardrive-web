import 'package:shared_preferences/shared_preferences.dart';

class KeyValueStore {
  late SharedPreferences _prefs;

  setup(SharedPreferences? instance) async {
    _prefs = instance ?? await SharedPreferences.getInstance();
  }

  Future<bool> putBool(String key, bool value) {
    return _prefs.setBool(key, value);
  }

  bool getBool(String key) {
    return _prefs.getBool(key) ?? false;
  }

  Future<bool> remove(String key) {
    return _prefs.remove(key);
  }
}
