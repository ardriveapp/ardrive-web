import 'dart:async';

import 'package:ardrive/drives_list/domain/drive_scope.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A heading in the sidebar that folds the rows under it away.
enum NavSection {
  publicDrives,
  privateDrives,
  sharedDrives,
  webPages,
  names;

  /// The drive group a drives heading is for.
  static NavSection forScope(DriveScope scope) => switch (scope) {
        DriveScope.public => publicDrives,
        DriveScope.private => privateDrives,
        DriveScope.sharedWithMe => sharedDrives,
        DriveScope.all ||
        DriveScope.hidden =>
          throw ArgumentError('$scope has no heading in the sidebar'),
      };
}

/// Which of the sidebar's headings the reader has folded away. All open to
/// begin with, the drive groups and Web pages and Names alike: one default
/// for every heading.
///
/// Held above the pages rather than in the sidebar, because there is no one
/// sidebar: each shell the router builds (a drive, the drives list, Web
/// pages, Names) draws its own, and the phone's drawer is built again each
/// time it opens. Kept in the sidebar, the folding was thrown away on every
/// move between them, so opening Web pages opened Public and Private again.
///
/// Saved with the user's preferences, so a reload keeps it too, and dropped
/// with them on logout: the next user's sidebar opens with every heading
/// open.
class NavSectionsCubit extends Cubit<Set<NavSection>> {
  NavSectionsCubit({UserPreferencesRepository? preferences})
      : _preferences = preferences,
        super(_read(preferences?.currentPreferences)) {
    // Preferences load after the app starts, again on login, and are
    // cleared on logout; each of those is followed.
    _subscription = preferences?.watch().listen((prefs) {
      final stored = _read(prefs);
      if (!setEquals(stored, state)) emit(stored);
    });
  }

  final UserPreferencesRepository? _preferences;
  StreamSubscription<UserPreferences>? _subscription;

  static Set<NavSection> _read(UserPreferences? prefs) => {
        for (final name in prefs?.foldedNavSections ?? const <String>{})
          // A name this build does not know is ignored, not an error.
          ...NavSection.values.where((s) => s.name == name),
      };

  bool isFolded(NavSection section) => state.contains(section);

  void toggle(NavSection section) {
    final next = state.contains(section)
        ? ({...state}..remove(section))
        : {...state, section};
    emit(next);
    _preferences?.saveFoldedNavSections({for (final s in next) s.name});
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}

/// For a nav widget that folds a heading: reads and toggles the app's
/// [NavSectionsCubit], or, in a tree that does not provide one (a widget
/// test of part of the nav), one of its own.
///
/// Follows the cubit, so folding read from preferences after the sidebar is
/// built, or cleared on logout, shows at once.
mixin FoldsNavSections<T extends StatefulWidget> on State<T> {
  NavSectionsCubit? _own;
  NavSectionsCubit? _sections;
  StreamSubscription<Set<NavSection>>? _changes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sections =
        context.read<NavSectionsCubit?>() ?? (_own ??= NavSectionsCubit());
    if (sections == _sections) return;
    _changes?.cancel();
    _sections = sections;
    _changes = sections.stream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  bool isFolded(NavSection section) => _sections!.isFolded(section);

  void toggleFolded(NavSection section) =>
      setState(() => _sections!.toggle(section));

  @override
  void dispose() {
    _changes?.cancel();
    _own?.close();
    super.dispose();
  }
}
