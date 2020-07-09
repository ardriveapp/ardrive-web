part of 'drives_bloc.dart';

abstract class DrivesEvent {}

class RefreshDrives extends DrivesEvent {}

class SelectDrive extends DrivesEvent {
  final String driveId;

  SelectDrive(this.driveId);
}

class AddDrive extends DrivesEvent {
  final DrivesCompanion drive;

  AddDrive({this.drive});
}

class DrivesUpdated extends DrivesEvent {
  final List<Drive> drives;

  DrivesUpdated({this.drives});
}
