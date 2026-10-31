import 'dart:async';

import 'package:ardrive/components/nav_sections.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPreferences extends Mock implements UserPreferencesRepository {}

UserPreferences _prefs(Set<String> folded) => UserPreferences(
      currentTheme: ArDriveThemes.light,
      lastSelectedDriveId: null,
      foldedNavSections: folded,
    );

/// A fold saved by a newer build, under a heading this build does not have,
/// is kept when this build saves: going back to that build finds the heading
/// as it was left. It used to be dropped on the next fold.
void main() {
  late _MockPreferences preferences;
  late StreamController<UserPreferences> changes;

  setUpAll(() => registerFallbackValue(<String>{}));

  setUp(() {
    preferences = _MockPreferences();
    changes = StreamController.broadcast(sync: true);
    addTearDown(changes.close);
    when(() => preferences.watch()).thenAnswer((_) => changes.stream);
    when(() => preferences.saveFoldedNavSections(any()))
        .thenAnswer((_) async {});
  });

  test('an unknown name read at start is saved back with each fold', () async {
    when(() => preferences.currentPreferences)
        .thenReturn(_prefs(const {'publicDrives', 'aNewerHeading'}));
    final cubit = NavSectionsCubit(preferences: preferences);
    addTearDown(cubit.close);

    expect(cubit.state, {NavSection.publicDrives});

    cubit.toggle(NavSection.names);
    verify(() => preferences.saveFoldedNavSections(
          {'aNewerHeading', 'publicDrives', 'names'},
        )).called(1);

    cubit.toggle(NavSection.publicDrives);
    verify(() => preferences.saveFoldedNavSections({'aNewerHeading', 'names'}))
        .called(1);
  });

  test('an unknown name in preferences read later is kept too', () async {
    when(() => preferences.currentPreferences).thenReturn(null);
    final cubit = NavSectionsCubit(preferences: preferences);
    addTearDown(cubit.close);

    changes.add(_prefs(const {'aNewerHeading'}));
    cubit.toggle(NavSection.webPages);
    verify(() =>
            preferences.saveFoldedNavSections({'aNewerHeading', 'webPages'}))
        .called(1);

    // Cleared on logout: nothing of the last user's is saved back.
    changes.add(_prefs(const {}));
    cubit.toggle(NavSection.sharedDrives);
    verify(() => preferences.saveFoldedNavSections({'sharedDrives'})).called(1);
  });

  test('focus folds every other heading, and saves once', () async {
    when(() => preferences.currentPreferences).thenReturn(_prefs(const {}));
    final cubit = NavSectionsCubit(preferences: preferences);
    addTearDown(cubit.close);

    cubit.focus(NavSection.webPages);
    cubit.focus(NavSection.webPages);

    expect(cubit.state, {...NavSection.values}..remove(NavSection.webPages));
    verify(() => preferences.saveFoldedNavSections(
          {'publicDrives', 'privateDrives', 'sharedDrives', 'names'},
        )).called(1);
  });
}
