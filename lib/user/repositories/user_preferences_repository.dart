import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive_ui/ardrive_ui.dart';

abstract class UserPreferencesRepository {
  Future<UserPreferences> load();
  Stream<UserPreferences> watch();
  Future<void> saveTheme(ArDriveThemes theme);
  Future<void> saveLastSelectedDriveId(String driveId);
  Future<void> saveShowHiddenFiles(bool showHiddenFiles);
  Future<void> clearLastSelectedDriveId();
  Future<void> saveUserHasHiddenItem(bool userHasHiddenDrive);

  factory UserPreferencesRepository({
    LocalKeyValueStore? store,
    required ThemeDetector themeDetector,
    required ArDriveAuth auth,
  }) {
    return _UserPreferencesRepository(
      store: store,
      themeDetector: themeDetector,
      auth: auth,
    );
  }
}

class _UserPreferencesRepository implements UserPreferencesRepository {
  LocalKeyValueStore? _store;
  final ThemeDetector _themeDetector;
  final ArDriveAuth _auth;

  _UserPreferencesRepository({
    LocalKeyValueStore? store,
    required ThemeDetector themeDetector,
    required ArDriveAuth auth,
  })  : _store = store,
        _themeDetector = themeDetector,
        _auth = auth,
        super() {
    _auth.onAuthStateChanged().listen((user) {
      if (user == null) {
        clearLastSelectedDriveId();
      }
    });
  }

  UserPreferences? _currentUserPreferences;
  final StreamController<UserPreferences> _userPreferencesController =
      StreamController.broadcast();

  @override
  Stream<UserPreferences> watch() {
    return _userPreferencesController.stream;
  }

  @override
  Future<UserPreferences> load() async {
    _store ??= await LocalKeyValueStore.getInstance();

    final currentTheme = _store!.getString('currentTheme') ??
        _themeDetector.getOSDefaultTheme().name;
    final lastSelectedDriveId = _store!.getString('lastSelectedDriveId');
    final showHiddenFiles = _store!.getBool('showHiddenFiles') ?? false;

    _currentUserPreferences = UserPreferences(
      currentTheme: _parseThemeFromLocalStorage(currentTheme),
      lastSelectedDriveId: lastSelectedDriveId,
      showHiddenFiles: showHiddenFiles,
      userHasHiddenDrive: _store!.getBool('userHasHiddenDrive') ?? false,
    );

    _userPreferencesController.sink.add(_currentUserPreferences!);

    return _currentUserPreferences!;
  }

  @override
  Future<void> saveTheme(ArDriveThemes theme) async {
    await _updatePreference(
      key: 'currentTheme',
      value: theme.name,
      updateFunction: (value) =>
          _currentUserPreferences!.copyWith(currentTheme: theme),
    );
  }

  @override
  Future<void> saveLastSelectedDriveId(String driveId) async {
    await _updatePreference(
      key: 'lastSelectedDriveId',
      value: driveId,
      updateFunction: (value) =>
          _currentUserPreferences!.copyWith(lastSelectedDriveId: value),
    );
  }

  @override
  Future<void> saveShowHiddenFiles(bool showHiddenFiles) async {
    await _updatePreference(
      key: 'showHiddenFiles',
      value: showHiddenFiles,
      updateFunction: (value) =>
          _currentUserPreferences!.copyWith(showHiddenFiles: value),
    );
  }

  @override
  Future<void> saveUserHasHiddenItem(bool userHasHiddenDrive) async {
    await _updatePreference(
      key: 'userHasHiddenDrive',
      value: userHasHiddenDrive,
      updateFunction: (value) =>
          _currentUserPreferences!.copyWith(userHasHiddenDrive: value),
    );
  }

  Future<LocalKeyValueStore> _getStore() async {
    _store ??= await LocalKeyValueStore.getInstance();

    return _store!;
  }

  @override
  Future<void> clearLastSelectedDriveId() async {
    (await _getStore()).remove('lastSelectedDriveId');

    _currentUserPreferences = _currentUserPreferences!.copyWith(
      lastSelectedDriveId: null,
    );

    _userPreferencesController.sink.add(_currentUserPreferences!);
  }

  // parse theme from string to ArDriveThemes
  ArDriveThemes _parseThemeFromLocalStorage(String theme) {
    switch (theme) {
      case 'light':
        return ArDriveThemes.light;
      case 'dark':
        return ArDriveThemes.dark;
      default:
        return ArDriveThemes.light;
    }
  }

  Future<void> _updatePreference<T>({
    required String key,
    required T value,
    required UserPreferences Function(T) updateFunction,
  }) async {
    _currentUserPreferences = updateFunction(value);
    _userPreferencesController.sink.add(_currentUserPreferences!);

    final store = await _getStore();
    if (value is String) {
      await store.putString(key, value as String);
    } else if (value is bool) {
      await store.putBool(key, value as bool);
    } else {
      throw ArgumentError('Unsupported type for preference value');
    }
  }
}
