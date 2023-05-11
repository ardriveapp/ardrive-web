import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockLocalKeyValueStore extends Mock implements LocalKeyValueStore {}

class MockThemeDetector extends Mock implements ThemeDetector {}

void main() {
  group('_UserPreferencesRepository', () {
    late UserPreferencesRepository repository;
    late MockLocalKeyValueStore mockStore;
    late MockThemeDetector mockThemeDetector;

    setUp(() {
      mockStore = MockLocalKeyValueStore();
      mockThemeDetector = MockThemeDetector();
      repository = UserPreferencesRepository(
        store: mockStore,
        themeDetector: mockThemeDetector,
      );
    });

    test('should return default OS theme if no theme is saved in storage',
        () async {
      when(() => mockStore.getString('currentTheme')).thenReturn(null);
      when(() => mockThemeDetector.getOSDefaultTheme())
          .thenReturn(ArDriveThemes.light);

      final result = await repository.load();

      expect(result, const UserPreferences(currentTheme: ArDriveThemes.light));
    });

    test('should return saved theme from storage', () async {
      when(() => mockStore.getString('currentTheme')).thenReturn('dark');

      final result = await repository.load();

      expect(result, const UserPreferences(currentTheme: ArDriveThemes.dark));
    });

    test('should save theme to storage', () async {
      when(() => mockStore.putString('currentTheme', ArDriveThemes.light.name))
          .thenAnswer((_) async => true);

      await repository.saveTheme(ArDriveThemes.light);

      verify(() =>
              mockStore.putString('currentTheme', ArDriveThemes.light.name))
          .called(1);
    });
  });
}
