part of 'drives_bloc.dart';

abstract class DrivesState {}

class DrivesLoadInProgress extends DrivesState {}

class DrivesLoadSuccess extends DrivesState {
  final String selectedDriveId;
  final List<Drive> drives;

  final bool canCreateNewDrive;

  DrivesLoadSuccess(
      {this.selectedDriveId, this.drives, this.canCreateNewDrive});
}
