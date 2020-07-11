part of 'drives_bloc.dart';

abstract class DrivesEvent {}

class RefreshDrives extends DrivesEvent {}

class SelectDrive extends DrivesEvent {
  final String driveId;

  SelectDrive(this.driveId);
}

class NewDrive extends DrivesEvent {
  final String driveName;

  NewDrive(this.driveName);
}

class DrivesUpdated extends DrivesEvent {
  final List<Drive> drives;

  DrivesUpdated({this.drives});
}
