import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:equatable/equatable.dart';

/// Sentinel used by copyWith to distinguish "not provided" from "explicitly null".
const _absent = Object();

class UserPreferences extends Equatable {
  final ArDriveThemes currentTheme;
  final String? lastSelectedDriveId;
  final bool showHiddenFiles;
  final bool userHasHiddenDrive;

  /// Whether logging in walks every drive's whole history.
  ///
  /// Defaults to false: a login should not spend the user's first minute on a
  /// full sync they did not ask for. A user who turned the setting on keeps
  /// the old behaviour, and one who turned it off is unaffected - only the
  /// never-touched case changes. The login path still refreshes the drive list
  /// either way, and still syncs when a transaction is left unresolved.
  final bool syncAllDrivesOnLogin;

  const UserPreferences({
    required this.currentTheme,
    required this.lastSelectedDriveId,
    this.showHiddenFiles = false,
    this.userHasHiddenDrive = false,
    this.syncAllDrivesOnLogin = false,
  });

  @override
  List<Object?> get props => [
        currentTheme.name,
        lastSelectedDriveId,
        showHiddenFiles,
        userHasHiddenDrive,
        syncAllDrivesOnLogin,
      ];

  UserPreferences copyWith({
    ArDriveThemes? currentTheme,
    Object? lastSelectedDriveId = _absent,
    bool? showHiddenFiles,
    bool? userHasHiddenDrive,
    bool? syncAllDrivesOnLogin,
  }) {
    return UserPreferences(
      currentTheme: currentTheme ?? this.currentTheme,
      lastSelectedDriveId: lastSelectedDriveId == _absent
          ? this.lastSelectedDriveId
          : lastSelectedDriveId as String?,
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      userHasHiddenDrive: userHasHiddenDrive ?? this.userHasHiddenDrive,
      syncAllDrivesOnLogin: syncAllDrivesOnLogin ?? this.syncAllDrivesOnLogin,
    );
  }
}
