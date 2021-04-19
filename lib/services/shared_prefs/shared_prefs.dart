import 'dart:html';

import 'package:shared_preferences/shared_preferences.dart';

class SharedPrefsService {
  static final SharedPrefsService _SharedPrefsService =
      SharedPrefsService._internal();

  factory SharedPrefsService() {
    return _SharedPrefsService;
  }
  SharedPreferences preferences;

  bool testnetEnabled = false;

  SharedPrefsService._internal() {
    loadPrefs();
  }

  void loadPrefs() async {
    preferences = await SharedPreferences.getInstance();
    testnetEnabled = preferences.getBool('testnetEnabled') ?? false;
  }

  void toggleTestNet(bool value) {
    preferences.setBool('testnetEnabled', value);
    testnetEnabled = value;
    window.location.reload();
  }

  //Save sync status of file, matching what's done in the desktop version.

  void setSyncStatus(String id, SyncStatus syncStatus) {
    preferences.setInt(id, syncStatus.index);
  }

  SyncStatus getSyncStatus(String id) {
    return SyncStatus.values[preferences.getInt(id)];
  }
}

enum SyncStatus {
  New,
  Uploaded,
  Confirmed,
}
