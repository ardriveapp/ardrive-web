part of 'drives_cubit.dart';

abstract class DrivesState {}

class DrivesLoadInProgress extends DrivesState {}

class DrivesLoadSuccess extends DrivesState {
  final String selectedDriveId;
  final List<Drive> drives;

  final bool canCreateNewDrive;

  DrivesLoadSuccess(
      {this.selectedDriveId, this.drives, this.canCreateNewDrive});

  DrivesLoadSuccess copyWith({
    String selectedDriveId,
    List<Drive> drives,
    bool canCreateNewDrive,
  }) =>
      DrivesLoadSuccess(
        selectedDriveId: selectedDriveId ?? this.selectedDriveId,
        drives: drives ?? this.drives,
        canCreateNewDrive: canCreateNewDrive ?? this.canCreateNewDrive,
      );
}
