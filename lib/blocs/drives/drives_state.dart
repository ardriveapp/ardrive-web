part of 'drives_cubit.dart';

abstract class DrivesState {}

class DrivesLoadInProgress extends DrivesState {}

class DrivesLoadSuccess extends DrivesState {
  final String selectedDriveId;
  final List<Drive> userDrives;
  final List<Drive> sharedDrives;

  final bool canCreateNewDrive;

  DrivesLoadSuccess({
    this.selectedDriveId,
    this.userDrives,
    this.sharedDrives,
    this.canCreateNewDrive,
  });

  DrivesLoadSuccess copyWith({
    String selectedDriveId,
    List<Drive> userDrives,
    List<Drive> sharedDrives,
    bool canCreateNewDrive,
  }) =>
      DrivesLoadSuccess(
        selectedDriveId: selectedDriveId ?? this.selectedDriveId,
        userDrives: userDrives ?? this.userDrives,
        sharedDrives: sharedDrives ?? this.sharedDrives,
        canCreateNewDrive: canCreateNewDrive ?? this.canCreateNewDrive,
      );
}
