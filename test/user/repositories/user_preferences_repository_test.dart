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
            syncAllDrivesOnLogin: false,
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
            syncAllDrivesOnLogin: false,
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
            syncAllDrivesOnLogin: false,
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

    group('the shipped default for syncing every drive on login', () {
      // A login should not walk every drive's whole history unasked. The
      // default moved to false; a stored value stays an explicit choice.
      test('is not to sync, before any storage is involved at all', () {
        const preferences = UserPreferences(
          currentTheme: ArDriveThemes.light,
          lastSelectedDriveId: null,
        );

        expect(preferences.syncAllDrivesOnLogin, false);
      });

      test('is not to sync when the user never touched the toggle', () async {
        when(() => mockStore.getString('currentTheme')).thenReturn('dark');
        when(() => mockStore.getString('lastSelectedDriveId')).thenReturn(null);
        when(() => mockStore.getBool('showHiddenFiles')).thenReturn(false);
        when(() => mockStore.getBool('userHasHiddenDrive')).thenReturn(false);
        // Nothing stored: the case every existing user who never opened
        // settings, and every new user, lands in.
        when(() => mockStore.getBool('syncAllDrivesOnLogin')).thenReturn(null);

        final result = await repository.load();

        expect(result.syncAllDrivesOnLogin, false);
      });

      test('is still to sync for a user who opted in', () async {
        when(() => mockStore.getString('currentTheme')).thenReturn('dark');
        when(() => mockStore.getString('lastSelectedDriveId')).thenReturn(null);
        when(() => mockStore.getBool('showHiddenFiles')).thenReturn(false);
        when(() => mockStore.getBool('userHasHiddenDrive')).thenReturn(false);
        when(() => mockStore.getBool('syncAllDrivesOnLogin')).thenReturn(true);

        final result = await repository.load();

        // An explicit yes is not quietly downgraded by the new default.
        expect(result.syncAllDrivesOnLogin, true);
      });
    });

    test('should save sync all drives on login preference to storage',
        () async {
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

    test('should clear preferences but preserve syncAllDrivesOnLogin',
        () async {
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
      // Logging out drops every local table, so a per-drive sync time kept
      // across it would sit over an empty drive.
      when(() => mockStore.remove('driveLastSyncedAt'))
          .thenAnswer((_) async => true);
      when(() => mockStore.remove('userHasHiddenDrive'))
          .thenAnswer((_) async => true);

      await repository.clear();

      // Verify cleared preferences
      verify(() => mockStore.remove('lastSelectedDriveId')).called(1);
      verify(() => mockStore.remove('showHiddenFiles')).called(1);
      verify(() => mockStore.remove('userHasHiddenDrive')).called(1);
      verify(() => mockStore.remove('driveLastSyncedAt')).called(1);
      // Verify syncAllDrivesOnLogin is NOT removed (should persist)
      verifyNever(() => mockStore.remove('syncAllDrivesOnLogin'));

      // Verify the actual preferences object has correct values
      final prefs = repository.currentPreferences!;
      expect(prefs.lastSelectedDriveId, isNull);
      expect(prefs.showHiddenFiles, false);
      expect(prefs.userHasHiddenDrive, false);
      expect(prefs.syncAllDrivesOnLogin, false);
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

    /// Per-drive sync times, which the drives list is built on.
    ///
    /// Stored here rather than as a `drives` column because it is a fact about
    /// this device: two browsers signed into one wallet have two different
    /// answers and both are right.
    group('when each drive was last synced', () {
      test('is empty for a store that has never held one', () async {
        when(() => mockStore.getString('driveLastSyncedAt')).thenReturn(null);

        final result = await repository.load();

        expect(result.driveLastSyncedAt, isEmpty);
      });

      test('reads back what was stored', () async {
        when(() => mockStore.getString('driveLastSyncedAt'))
            .thenReturn('{"drive-a":1700000000000}');

        final result = await repository.load();

        expect(
          result.driveLastSyncedAt['drive-a'],
          DateTime.fromMillisecondsSinceEpoch(1700000000000),
        );
      });

      test('an unreadable value reads as never synced, not as a crash',
          () async {
        when(() => mockStore.getString('driveLastSyncedAt'))
            .thenReturn('not json at all');

        final result = await repository.load();

        expect(result.driveLastSyncedAt, isEmpty);
      });

      test('records the drives a sync covered', () async {
        when(() => mockStore.getString('driveLastSyncedAt')).thenReturn(null);
        when(() => mockStore.putString('driveLastSyncedAt', any()))
            .thenAnswer((_) async => true);
        await repository.load();

        final at = DateTime.fromMillisecondsSinceEpoch(1700000000000);
        await repository.saveDrivesLastSynced(['drive-a', 'drive-b'], at: at);

        verify(
          () => mockStore.putString(
            'driveLastSyncedAt',
            '{"drive-a":1700000000000,"drive-b":1700000000000}',
          ),
        ).called(1);

        expect(repository.currentPreferences!.driveLastSyncedAt, {
          'drive-a': at,
          'drive-b': at,
        });
      });

      test('a single-drive sync leaves the other drives as stale as they were',
          () async {
        when(() => mockStore.getString('driveLastSyncedAt'))
            .thenReturn('{"drive-a":1700000000000}');
        when(() => mockStore.putString('driveLastSyncedAt', any()))
            .thenAnswer((_) async => true);
        await repository.load();

        await repository.saveDrivesLastSynced(
          ['drive-b'],
          at: DateTime.fromMillisecondsSinceEpoch(1800000000000),
        );

        final stored = repository.currentPreferences!.driveLastSyncedAt;

        expect(
          stored['drive-a'],
          DateTime.fromMillisecondsSinceEpoch(1700000000000),
        );
        expect(
          stored['drive-b'],
          DateTime.fromMillisecondsSinceEpoch(1800000000000),
        );
      });

      test('a sync that covered nothing writes nothing', () async {
        when(() => mockStore.getString('driveLastSyncedAt')).thenReturn(null);
        await repository.load();

        await repository.saveDrivesLastSynced(const []);

        verifyNever(() => mockStore.putString('driveLastSyncedAt', any()));
      });
    });
  });
}
