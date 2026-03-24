import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../core/upload/uploader_test.dart';

class MockLocalKeyValueStore extends Mock implements LocalKeyValueStore {}

class MockThemeDetector extends Mock implements ThemeDetector {}

void main() {
  group('_UserPreferencesRepository', () {
    late UserPreferencesRepository repository;
    late MockLocalKeyValueStore mockStore;
    late MockThemeDetector mockThemeDetector;
    late MockArDriveAuth mockAuth;

    /// Helper to set up default stubs that are needed when auth emits a user
    /// (which triggers load() in the repository constructor)
    void setUpDefaultStubs() {
      when(() => mockStore.getString('currentTheme')).thenReturn(null);
      when(() => mockStore.getString('lastSelectedDriveId')).thenReturn(null);
      when(() => mockStore.getBool('showHiddenFiles')).thenReturn(false);
      when(() => mockStore.getBool('userHasHiddenDrive')).thenReturn(false);
      when(() => mockStore.getBool('syncAllDrivesOnLogin')).thenReturn(null);
      when(() => mockThemeDetector.getOSDefaultTheme())
          .thenReturn(ArDriveThemes.light);
    }

    setUp(() {
      mockStore = MockLocalKeyValueStore();
      mockThemeDetector = MockThemeDetector();
      mockAuth = MockArDriveAuth();
      // Set up default stubs BEFORE creating repository, since auth listener
      // triggers load() when user is emitted
      setUpDefaultStubs();
      when(() => mockAuth.onAuthStateChanged())
          .thenAnswer((_) => Stream.value(getFakeUser()));
      repository = UserPreferencesRepository(
        store: mockStore,
        themeDetector: mockThemeDetector,
        auth: mockAuth,
      );
    });

    test('should return default OS theme if no theme is saved in storage',
        () async {
      when(() => mockStore.getString('currentTheme')).thenReturn(null);
      when(() => mockStore.getString('lastSelectedDriveId')).thenReturn(null);
      when(() => mockThemeDetector.getOSDefaultTheme())
          .thenReturn(ArDriveThemes.light);
      when(() => mockStore.getBool('showHiddenFiles')).thenReturn(false);
      when(() => mockStore.getBool('userHasHiddenDrive')).thenReturn(false);
      when(() => mockStore.getBool('syncAllDrivesOnLogin')).thenReturn(null);

      final result = await repository.load();

      expect(
          result,
          const UserPreferences(
            currentTheme: ArDriveThemes.light,
            lastSelectedDriveId: null,
            showHiddenFiles: false,
            userHasHiddenDrive: false,
            syncAllDrivesOnLogin: true,
          ));
    });

    test('should return saved theme from storage', () async {
      when(() => mockStore.getString('currentTheme')).thenReturn('dark');
      when(() => mockStore.getString('lastSelectedDriveId')).thenReturn(null);
      when(() => mockStore.getBool('showHiddenFiles')).thenReturn(false);
      when(() => mockStore.getBool('userHasHiddenDrive')).thenReturn(false);
      when(() => mockStore.getBool('syncAllDrivesOnLogin')).thenReturn(null);

      final result = await repository.load();

      expect(
          result,
          const UserPreferences(
            currentTheme: ArDriveThemes.dark,
            lastSelectedDriveId: null,
            showHiddenFiles: false,
            userHasHiddenDrive: false,
            syncAllDrivesOnLogin: true,
          ));
    });

    test('should save theme to storage', () async {
      // Setup initial load
      when(() => mockStore.getString('currentTheme')).thenReturn('dark');
      when(() => mockStore.getString('lastSelectedDriveId')).thenReturn(null);
      when(() => mockStore.getBool('showHiddenFiles')).thenReturn(false);
      when(() => mockStore.getBool('userHasHiddenDrive')).thenReturn(false);
      when(() => mockStore.getBool('syncAllDrivesOnLogin')).thenReturn(null);
      await repository.load();

      when(() => mockStore.putString('currentTheme', ArDriveThemes.light.name))
          .thenAnswer((_) async => true);

      await repository.saveTheme(ArDriveThemes.light);

      verify(() =>
              mockStore.putString('currentTheme', ArDriveThemes.light.name))
          .called(1);
    });

    test('should save last selected drive id to storage', () async {
      // Setup initial load
      when(() => mockStore.getString('currentTheme')).thenReturn('dark');
      when(() => mockStore.getString('lastSelectedDriveId')).thenReturn(null);
      when(() => mockStore.getBool('showHiddenFiles')).thenReturn(false);
      when(() => mockStore.getBool('userHasHiddenDrive')).thenReturn(false);
      when(() => mockStore.getBool('syncAllDrivesOnLogin')).thenReturn(null);
      await repository.load();

      when(() => mockStore.putString('lastSelectedDriveId', 'drive_id'))
          .thenAnswer((_) async => true);

      await repository.saveLastSelectedDriveId('drive_id');

      verify(() => mockStore.putString('lastSelectedDriveId', 'drive_id'))
          .called(1);
    });

    test('should return last selected drive id from storage', () async {
      when(() => mockStore.getString('lastSelectedDriveId'))
          .thenReturn('drive_id');
      when(() => mockStore.getString('currentTheme')).thenReturn('dark');
      when(() => mockStore.getBool('showHiddenFiles')).thenReturn(false);
      when(() => mockStore.getBool('userHasHiddenDrive')).thenReturn(false);
      when(() => mockStore.getBool('syncAllDrivesOnLogin')).thenReturn(null);

      final result = await repository.load();

      expect(
          result,
          const UserPreferences(
            currentTheme: ArDriveThemes.dark,
            lastSelectedDriveId: 'drive_id',
            showHiddenFiles: false,
            userHasHiddenDrive: false,
            syncAllDrivesOnLogin: true,
          ));
    });

    test('should save show hidden files preference to storage', () async {
      // Setup initial load
      when(() => mockStore.getString('currentTheme')).thenReturn('dark');
      when(() => mockStore.getString('lastSelectedDriveId')).thenReturn(null);
      when(() => mockStore.getBool('showHiddenFiles')).thenReturn(false);
      when(() => mockStore.getBool('userHasHiddenDrive')).thenReturn(false);
      when(() => mockStore.getBool('syncAllDrivesOnLogin')).thenReturn(null);
      await repository.load();

      when(() => mockStore.putBool('showHiddenFiles', true))
          .thenAnswer((_) async => true);

      await repository.saveShowHiddenFiles(true);

      verify(() => mockStore.putBool('showHiddenFiles', true)).called(1);
    });

    test('should save user has hidden item preference to storage', () async {
      // Setup initial load
      when(() => mockStore.getString('currentTheme')).thenReturn('dark');
      when(() => mockStore.getString('lastSelectedDriveId')).thenReturn(null);
      when(() => mockStore.getBool('showHiddenFiles')).thenReturn(false);
      when(() => mockStore.getBool('userHasHiddenDrive')).thenReturn(false);
      when(() => mockStore.getBool('syncAllDrivesOnLogin')).thenReturn(null);
      await repository.load();

      when(() => mockStore.putBool('userHasHiddenDrive', true))
          .thenAnswer((_) async => true);

      await repository.saveUserHasHiddenItem(true);

      verify(() => mockStore.putBool('userHasHiddenDrive', true)).called(1);
    });

    test('should save sync all drives on login preference to storage', () async {
      // Setup initial load
      when(() => mockStore.getString('currentTheme')).thenReturn('dark');
      when(() => mockStore.getString('lastSelectedDriveId')).thenReturn(null);
      when(() => mockStore.getBool('showHiddenFiles')).thenReturn(false);
      when(() => mockStore.getBool('userHasHiddenDrive')).thenReturn(false);
      when(() => mockStore.getBool('syncAllDrivesOnLogin')).thenReturn(true);
      await repository.load();

      when(() => mockStore.putBool('syncAllDrivesOnLogin', false))
          .thenAnswer((_) async => true);

      await repository.saveSyncAllDrivesOnLogin(false);

      verify(() => mockStore.putBool('syncAllDrivesOnLogin', false)).called(1);
    });

    test('should clear preferences but preserve syncAllDrivesOnLogin', () async {
      // Setup initial load
      when(() => mockStore.getString('currentTheme')).thenReturn('dark');
      when(() => mockStore.getString('lastSelectedDriveId'))
          .thenReturn('drive_id');
      when(() => mockStore.getBool('showHiddenFiles')).thenReturn(true);
      when(() => mockStore.getBool('userHasHiddenDrive')).thenReturn(true);
      when(() => mockStore.getBool('syncAllDrivesOnLogin')).thenReturn(false);
      await repository.load();

      when(() => mockStore.remove('lastSelectedDriveId'))
          .thenAnswer((_) async => true);
      when(() => mockStore.remove('showHiddenFiles'))
          .thenAnswer((_) async => true);
      when(() => mockStore.remove('userHasHiddenDrive'))
          .thenAnswer((_) async => true);

      await repository.clear();

      // Verify cleared preferences
      verify(() => mockStore.remove('lastSelectedDriveId')).called(1);
      verify(() => mockStore.remove('showHiddenFiles')).called(1);
      verify(() => mockStore.remove('userHasHiddenDrive')).called(1);
      // Verify syncAllDrivesOnLogin is NOT removed (should persist)
      verifyNever(() => mockStore.remove('syncAllDrivesOnLogin'));
    });

    test(
      'should watch for changes in user preferences',
      () async {
        const initialPreferences = UserPreferences(
          currentTheme: ArDriveThemes.light,
          lastSelectedDriveId: null,
          showHiddenFiles: false,
          userHasHiddenDrive: false,
          syncAllDrivesOnLogin: true,
        );

        when(() => mockStore.getString('currentTheme')).thenReturn('light');
        when(() => mockStore.getString('lastSelectedDriveId')).thenReturn(null);
        when(() => mockStore.getBool('showHiddenFiles')).thenReturn(false);
        when(() => mockStore.getBool('userHasHiddenDrive')).thenReturn(false);
        when(() => mockStore.getBool('syncAllDrivesOnLogin')).thenReturn(true);

        final stream = repository.watch();
        // Use a StreamQueue to easily work with the stream in tests
        final queue = StreamQueue(stream);

        await repository.load(); // Ensure initial preferences are loaded

        expect(
          await queue.next,
          equals(initialPreferences),
        );

        // Clean up
        await queue.cancel();
      },
    );

    test(
      'should emit updated preferences after save operations',
      () async {
        // Setup initial state
        when(() => mockStore.getString('currentTheme')).thenReturn('light');
        when(() => mockStore.getString('lastSelectedDriveId')).thenReturn(null);
        when(() => mockStore.getBool('showHiddenFiles')).thenReturn(false);
        when(() => mockStore.getBool('userHasHiddenDrive')).thenReturn(false);
        when(() => mockStore.getBool('syncAllDrivesOnLogin')).thenReturn(true);
        await repository.load();

        // Setup save stubs
        when(() => mockStore.putString('currentTheme', ArDriveThemes.dark.name))
            .thenAnswer((_) async => true);

        // Listen to stream and collect the emission from saveTheme
        final stream = repository.watch();
        final queue = StreamQueue(stream);

        await repository.saveTheme(ArDriveThemes.dark);

        // Verify the emitted preferences reflect the change
        final emitted = await queue.next;
        expect(emitted.currentTheme, equals(ArDriveThemes.dark));

        await queue.cancel();
      },
    );
  });
}
