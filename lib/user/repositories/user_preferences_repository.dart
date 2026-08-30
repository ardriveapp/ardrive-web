import 'dart:async';
import 'dart:convert';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive_ui/ardrive_ui.dart';

abstract class UserPreferencesRepository {
  Future<UserPreferences> load();
  Stream<UserPreferences> watch();
  UserPreferences? get currentPreferences;
  Future<void> saveTheme(ArDriveThemes theme);
  Future<void> saveLastSelectedDriveId(String driveId);
  Future<void> saveShowHiddenFiles(bool showHiddenFiles);
  Future<void> clear();
  Future<void> saveUserHasHiddenItem(bool userHasHiddenDrive);
  Future<void> saveSyncAllDrivesOnLogin(bool syncAllDrivesOnLogin);

  /// Records that these drives have just been walked to the end.
  ///
  /// Called with every drive a finished sync covered, so an all-drives sync
  /// writes one timestamp across the wallet and a single-drive sync writes one
  /// for that drive. Drives a sync failed on are deliberately not passed: a
  /// drive that could not be read was not synced, and saying otherwise is the
  /// exact kind of confident wrong answer this series exists to remove.
  Future<void> saveDrivesLastSynced(Iterable<String> driveIds, {DateTime? at});

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

/// Where the per-drive sync times are kept, as a JSON object of drive id to
/// milliseconds since epoch.
///
/// One key holding a map rather than a key per drive: the store is a flat
/// namespace shared with everything else the app persists, and a wallet with
/// thirty drives should not leave thirty stray keys behind it.
const _driveLastSyncedAtKey = 'driveLastSyncedAt';

Map<String, DateTime> _decodeDriveLastSyncedAt(String? stored) {
  if (stored == null || stored.isEmpty) {
    return const {};
  }

  try {
    final decoded = jsonDecode(stored);

    if (decoded is! Map) {
      return const {};
    }

    final result = <String, DateTime>{};

    decoded.forEach((key, value) {
      if (key is String && value is int) {
        result[key] = DateTime.fromMillisecondsSinceEpoch(value);
      }
    });

    return result;
  } catch (_) {
    // Unreadable is the same as unknown. A drive whose timestamp cannot be
    // parsed reads as never synced, which is the honest answer and the one the
    // page already knows how to draw.
    return const {};
  }
}

String _encodeDriveLastSyncedAt(Map<String, DateTime> value) => jsonEncode({
      for (final entry in value.entries)
        entry.key: entry.value.millisecondsSinceEpoch,
    });

class _UserPreferencesRepository implements UserPreferencesRepository {
  LocalKeyValueStore? _store;
  final ThemeDetector _themeDetector;
  final ArDriveAuth _auth;

  /// Serializes auth state operations to prevent race conditions
  Future<void>? _authStateWork;

  _UserPreferencesRepository({
    LocalKeyValueStore? store,
    required ThemeDetector themeDetector,
    required ArDriveAuth auth,
  })  : _store = store,
        _themeDetector = themeDetector,
        _auth = auth,
        super() {
    _auth.onAuthStateChanged().listen((user) {
      // Chain auth state operations to ensure ordered execution
      _authStateWork = (_authStateWork ?? Future.value()).then((_) {
        if (user == null) {
          return clear();
        } else {
          // When user logs in, reload preferences to emit current values to stream
          return load();
        }
      });
    });
  }

  UserPreferences? _currentUserPreferences;
  final StreamController<UserPreferences> _userPreferencesController =
      StreamController.broadcast();

  @override
  UserPreferences? get currentPreferences => _currentUserPreferences;

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
    final driveLastSyncedAt =
        _decodeDriveLastSyncedAt(_store!.getString(_driveLastSyncedAtKey));
    // Nothing stored means the user never touched the toggle, and the shipped
    // default is not to sync on login. A stored value - either way - is an
    // explicit choice and is honoured as it stands.
    final syncAllDrivesOnLogin =
        _store!.getBool('syncAllDrivesOnLogin') ?? false;

    _currentUserPreferences = UserPreferences(
      currentTheme: _parseThemeFromLocalStorage(currentTheme),
      lastSelectedDriveId: lastSelectedDriveId,
      showHiddenFiles: showHiddenFiles,
      userHasHiddenDrive: _store!.getBool('userHasHiddenDrive') ?? false,
      syncAllDrivesOnLogin: syncAllDrivesOnLogin,
      driveLastSyncedAt: driveLastSyncedAt,
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

  @override
  Future<void> saveSyncAllDrivesOnLogin(bool syncAllDrivesOnLogin) async {
    await _updatePreference(
      key: 'syncAllDrivesOnLogin',
      value: syncAllDrivesOnLogin,
      updateFunction: (value) =>
          _currentUserPreferences!.copyWith(syncAllDrivesOnLogin: value),
    );
  }

  @override
  Future<void> saveDrivesLastSynced(
    Iterable<String> driveIds, {
    DateTime? at,
  }) async {
    if (driveIds.isEmpty) {
      return;
    }

    if (_currentUserPreferences == null) {
      await load();
    }

    final when = at ?? DateTime.now();

    // Merged rather than replaced: a single-drive sync must not erase what the
    // other drives were last known to be.
    final merged = Map<String, DateTime>.from(
      _currentUserPreferences!.driveLastSyncedAt,
    );

    for (final driveId in driveIds) {
      merged[driveId] = when;
    }

    await _updatePreference(
      key: _driveLastSyncedAtKey,
      value: _encodeDriveLastSyncedAt(merged),
      updateFunction: (_) =>
          _currentUserPreferences!.copyWith(driveLastSyncedAt: merged),
    );
  }

  Future<LocalKeyValueStore> _getStore() async {
    _store ??= await LocalKeyValueStore.getInstance();

    return _store!;
  }

  @override
  Future<void> clear() async {
    (await _getStore()).remove('lastSelectedDriveId');
    (await _getStore()).remove('showHiddenFiles');
    (await _getStore()).remove('userHasHiddenDrive');
    // Logging out drops every local table (`deleteAllTables`), so every drive
    // is about to read as never synced whether this is cleared or not. Keeping
    // it would leave "Synced 2 hours ago" sitting over an empty drive.
    (await _getStore()).remove(_driveLastSyncedAtKey);
    // Note: syncAllDrivesOnLogin is NOT cleared - it's a global preference
    // that should persist across sessions and logins

    // If preferences haven't been loaded yet, load them first
    if (_currentUserPreferences == null) {
      await load();
      return; // load() already emits to stream
    }

    _currentUserPreferences = _currentUserPreferences!.copyWith(
      lastSelectedDriveId: null,
      showHiddenFiles: false,
      userHasHiddenDrive: false,
      driveLastSyncedAt: const {},
      // Keep syncAllDrivesOnLogin unchanged
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
    // Ensure preferences are loaded before updating
    if (_currentUserPreferences == null) {
      await load();
    }

    _currentUserPreferences = updateFunction(value);

    final store = await _getStore();
    if (value is String) {
      await store.putString(key, value as String);
    } else if (value is bool) {
      await store.putBool(key, value as bool);
    } else {
      throw ArgumentError('Unsupported type for preference value');
    }

    // Notify listeners after save completes
    if (_currentUserPreferences != null) {
      _userPreferencesController.sink.add(_currentUserPreferences!);
    }
  }
}
