import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
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

      final result = await repository.load();

      expect(
          result,
          const UserPreferences(
              currentTheme: ArDriveThemes.light, lastSelectedDriveId: null));
    });

    test('should return saved theme from storage', () async {
      when(() => mockStore.getString('currentTheme')).thenReturn('dark');
      when(() => mockAuth.onAuthStateChanged())
          .thenAnswer((_) => Stream.value(getFakeUser()));

      final result = await repository.load();

      expect(
          result,
          const UserPreferences(
              currentTheme: ArDriveThemes.dark, lastSelectedDriveId: null));
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
    });

    test('should return last selected drive id from storage', () async {
      when(() => mockStore.getString('lastSelectedDriveId'))
          .thenReturn('drive_id');
      final result = await repository.load();

      expect(
          result,
          const UserPreferences(
              currentTheme: ArDriveThemes.dark,
              lastSelectedDriveId: 'drive_id'));
    });
  });
}
