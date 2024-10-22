import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:equatable/equatable.dart';

class UserPreferences extends Equatable {
  final ArDriveThemes currentTheme;
  final String? lastSelectedDriveId;
  final bool showHiddenFiles;
  final bool userHasHiddenDrive;

  const UserPreferences({
    required this.currentTheme,
    required this.lastSelectedDriveId,
    this.showHiddenFiles = false,
    this.userHasHiddenDrive = false,
  });

  @override
  List<Object?> get props => [
        currentTheme.name,
        lastSelectedDriveId,
        showHiddenFiles,
        userHasHiddenDrive,
      ];

  UserPreferences copyWith({
    ArDriveThemes? currentTheme,
    String? lastSelectedDriveId,
    bool? showHiddenFiles,
    bool? userHasHiddenDrive,
  }) {
    return UserPreferences(
      currentTheme: currentTheme ?? this.currentTheme,
      lastSelectedDriveId: lastSelectedDriveId ?? this.lastSelectedDriveId,
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      userHasHiddenDrive: userHasHiddenDrive ?? this.userHasHiddenDrive,
    );
  }
}
