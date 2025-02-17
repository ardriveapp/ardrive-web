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

    setUpAll(() {
      mockStore = MockLocalKeyValueStore();
      mockThemeDetector = MockThemeDetector();
      mockAuth = MockArDriveAuth();
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
      when(() => mockThemeDetector.getOSDefaultTheme())
          .thenReturn(ArDriveThemes.light);
      when(() => mockStore.getBool('showHiddenFiles')).thenReturn(false);
      when(() => mockStore.getBool('userHasHiddenDrive')).thenReturn(false);

      final result = await repository.load();

      expect(
          result,
          const UserPreferences(
            currentTheme: ArDriveThemes.light,
            lastSelectedDriveId: null,
            showHiddenFiles: false,
            userHasHiddenDrive: false,
          ));
    });

    test('should return saved theme from storage', () async {
      when(() => mockStore.getString('currentTheme')).thenReturn('dark');
      when(() => mockStore.getBool('showHiddenFiles')).thenReturn(false);
      when(() => mockStore.getBool('userHasHiddenDrive')).thenReturn(false);
      when(() => mockAuth.onAuthStateChanged())
          .thenAnswer((_) => Stream.value(getFakeUser()));

      final result = await repository.load();

      expect(
          result,
          const UserPreferences(
            currentTheme: ArDriveThemes.dark,
            lastSelectedDriveId: null,
            showHiddenFiles: false,
            userHasHiddenDrive: false,
          ));
    });

    test('should save theme to storage', () async {
      when(() => mockStore.putString('currentTheme', ArDriveThemes.light.name))
          .thenAnswer((_) async => true);

      await repository.saveTheme(ArDriveThemes.light);

      verify(() =>
              mockStore.putString('currentTheme', ArDriveThemes.light.name))
          .called(1);
    });

    test('should save last selected drive id to storage', () async {
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

      final result = await repository.load();

      expect(
          result,
          const UserPreferences(
            currentTheme: ArDriveThemes.dark,
            lastSelectedDriveId: 'drive_id',
            showHiddenFiles: false,
            userHasHiddenDrive: false,
          ));
    });

    test('should save show hidden files preference to storage', () async {
      when(() => mockStore.putBool('showHiddenFiles', true))
          .thenAnswer((_) async => true);

      await repository.saveShowHiddenFiles(true);

      verify(() => mockStore.putBool('showHiddenFiles', true)).called(1);
    });

    test('should save user has hidden item preference to storage', () async {
      when(() => mockStore.putBool('userHasHiddenDrive', true))
          .thenAnswer((_) async => true);

      await repository.saveUserHasHiddenItem(true);

      verify(() => mockStore.putBool('userHasHiddenDrive', true)).called(1);
    });

    test('should clear last selected drive id from storage', () async {
      when(() => mockStore.remove('lastSelectedDriveId'))
          .thenAnswer((_) async => true);
      when(() => mockStore.remove('showHiddenFiles'))
          .thenAnswer((_) async => true);
      when(() => mockStore.remove('userHasHiddenDrive'))
          .thenAnswer((_) async => true);

      await repository.clear();

      verify(() => mockStore.remove('lastSelectedDriveId')).called(1);
    });

    test(
      'should watch for changes in user preferences',
      () async {
        const initialPreferences = UserPreferences(
          currentTheme: ArDriveThemes.light,
          lastSelectedDriveId: null,
          showHiddenFiles: false,
          userHasHiddenDrive: false,
        );

        when(() => mockStore.getString('currentTheme')).thenReturn('light');
        when(() => mockStore.getString('lastSelectedDriveId')).thenReturn(null);
        when(() => mockStore.getBool('showHiddenFiles')).thenReturn(false);
        when(() => mockStore.getBool('userHasHiddenDrive')).thenReturn(false);

        final stream = repository.watch();
        // Use a StreamQueue to easily work with the stream in tests
        final queue = StreamQueue(stream);

        await repository.load(); // Ensure initial preferences are loaded

        expect(
          await queue.next,
          equals(initialPreferences),
        );

        when(() => mockStore.putString('currentTheme', ArDriveThemes.dark.name))
            .thenAnswer((_) async => true);
        when(() => mockStore.putString('lastSelectedDriveId', 'new_drive_id'))
            .thenAnswer((_) async => true);
        when(() => mockStore.putBool('showHiddenFiles', true))
            .thenAnswer((_) async => true);
        when(() => mockStore.putBool('userHasHiddenDrive', true))
            .thenAnswer((_) async => true);

        // Simulate changes in preferences
        when(() => mockStore.getString('currentTheme')).thenReturn('dark');
        when(() => mockStore.getString('lastSelectedDriveId'))
            .thenReturn('new_drive_id');
        when(() => mockStore.getBool('showHiddenFiles')).thenReturn(true);
        when(() => mockStore.getBool('userHasHiddenDrive')).thenReturn(true);

        // Trigger preference changes
        await repository.saveTheme(ArDriveThemes.dark);
        await repository.saveLastSelectedDriveId('new_drive_id');
        await repository.saveShowHiddenFiles(true);
        await repository.saveUserHasHiddenItem(true);

        await repository.load();

        expect(
          await queue.next,
          const UserPreferences(
            currentTheme: ArDriveThemes.dark,
            lastSelectedDriveId: 'new_drive_id',
            showHiddenFiles: true,
            userHasHiddenDrive: true,
          ),
        );

        // Clean up
        await queue.cancel();
      },
    );
  });
}
