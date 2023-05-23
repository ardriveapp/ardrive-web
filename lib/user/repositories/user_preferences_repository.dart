import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive_ui/ardrive_ui.dart';

abstract class UserPreferencesRepository {
  Future<UserPreferences> load();
  Future<void> saveTheme(ArDriveThemes theme);

  factory UserPreferencesRepository({
    LocalKeyValueStore? store,
    required ThemeDetector themeDetector,
  }) {
    return _UserPreferencesRepository(
      store: store,
      themeDetector: themeDetector,
    );
  }
}

class _UserPreferencesRepository implements UserPreferencesRepository {
  LocalKeyValueStore? _store;
  final ThemeDetector _themeDetector;

  _UserPreferencesRepository({
    LocalKeyValueStore? store,
    required ThemeDetector themeDetector,
  })  : _store = store,
        _themeDetector = themeDetector;

  @override
  Future<UserPreferences> load() async {
    _store ??= await LocalKeyValueStore.getInstance();

    final currentTheme = _store!.getString('currentTheme');

    if (currentTheme != null) {
      return UserPreferences(
        currentTheme: _parseThemeFromLocalStorage(currentTheme),
      );
    }

    return UserPreferences(
      currentTheme: _themeDetector.getOSDefaultTheme(),
    );
  }

  @override
  Future<void> saveTheme(ArDriveThemes theme) async {
    (await _getStore()).putString(
      'currentTheme',
      theme.name,
    );
  }

  Future<LocalKeyValueStore> _getStore() async {
    _store ??= await LocalKeyValueStore.getInstance();

    return _store!;
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
}
