import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:equatable/equatable.dart';

/// Sentinel used by copyWith to distinguish "not provided" from "explicitly null".
const _absent = Object();

class UserPreferences extends Equatable {
  final ArDriveThemes currentTheme;
  final String? lastSelectedDriveId;
  final bool showHiddenFiles;
  final bool userHasHiddenDrive;
  final bool syncAllDrivesOnLogin;

  const UserPreferences({
    required this.currentTheme,
    required this.lastSelectedDriveId,
    this.showHiddenFiles = false,
    this.userHasHiddenDrive = false,
    this.syncAllDrivesOnLogin = true,
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
