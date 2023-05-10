import 'package:ardrive/theme/theme_switcher_bloc.dart';
import 'package:ardrive/theme/theme_switcher_state.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

void main() {
  group('ThemeSwitcherBloc', () {
    late UserPreferencesRepository userPreferencesRepository;
    late ThemeSwitcherBloc themeSwitcherBloc;

    setUp(() {
      userPreferencesRepository = MockUserPreferencesRepository();
      themeSwitcherBloc = ThemeSwitcherBloc(
        userPreferencesRepository: userPreferencesRepository,
      );
    });

    test('initial state is ThemeSwitcherInProgress', () {
      expect(themeSwitcherBloc.state, ThemeSwitcherInProgress());
    });

    blocTest<ThemeSwitcherBloc, ThemeSwitcherState>(
      'emits ThemeSwitcherLightTheme when LoadTheme succeeds with light theme',
      build: () {
        when(() => userPreferencesRepository.load()).thenAnswer(
          (_) async => const UserPreferences(currentTheme: ArDriveThemes.light),
        );
        return themeSwitcherBloc;
      },
      act: (bloc) => bloc.add(LoadTheme()),
      expect: () => [ThemeSwitcherInProgress(), ThemeSwitcherLightTheme()],
    );

    blocTest<ThemeSwitcherBloc, ThemeSwitcherState>(
      'emits ThemeSwitcherDarkTheme when LoadTheme succeeds with dark theme',
      build: () {
        when(() => userPreferencesRepository.load()).thenAnswer(
          (_) async => const UserPreferences(currentTheme: ArDriveThemes.dark),
        );
        return themeSwitcherBloc;
      },
      act: (bloc) => bloc.add(LoadTheme()),
      expect: () => [ThemeSwitcherInProgress(), ThemeSwitcherDarkTheme()],
    );

    blocTest<ThemeSwitcherBloc, ThemeSwitcherState>(
      'emits ThemeSwitcherDarkTheme when ChangeTheme from ThemeSwitcherLightTheme',
      build: () {
        when(() => userPreferencesRepository.load()).thenAnswer(
          (_) async => const UserPreferences(currentTheme: ArDriveThemes.light),
        );
        when(() => userPreferencesRepository.saveTheme(ArDriveThemes.dark))
            .thenAnswer((_) => Future.value());

        return themeSwitcherBloc;
      },
      act: (bloc) {
        bloc.add(LoadTheme());
        bloc.add(ChangeTheme());
      },
      expect: () => [
        ThemeSwitcherInProgress(),
        ThemeSwitcherLightTheme(),
        ThemeSwitcherDarkTheme(),
      ],
    );

    blocTest<ThemeSwitcherBloc, ThemeSwitcherState>(
      'emits ThemeSwitcherLightTheme when ChangeTheme from ThemeSwitcherDarkTheme',
      build: () {
        when(() => userPreferencesRepository.load()).thenAnswer(
          (_) async => const UserPreferences(currentTheme: ArDriveThemes.dark),
        );
        when(() => userPreferencesRepository.saveTheme(ArDriveThemes.light))
            .thenAnswer((_) => Future.value());

        return themeSwitcherBloc;
      },
      act: (bloc) {
        bloc.add(LoadTheme());
        bloc.add(ChangeTheme());
      },
      expect: () => [
        ThemeSwitcherInProgress(),
        ThemeSwitcherDarkTheme(),
        ThemeSwitcherLightTheme(),
      ],
    );

    tearDown(() {
      themeSwitcherBloc.close();
    });
  });
}
