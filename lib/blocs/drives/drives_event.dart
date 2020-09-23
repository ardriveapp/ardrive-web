part of 'drives_bloc.dart';

abstract class DrivesEvent {}

class SelectDrive extends DrivesEvent {
  final String driveId;

  SelectDrive(this.driveId);
}

class NewDrive extends DrivesEvent {
  final String driveName;
  final String drivePrivacy;

  NewDrive(this.driveName, this.drivePrivacy);
}

class DrivesUpdated extends DrivesEvent {
  final List<Drive> drives;

  DrivesUpdated({this.drives});
}
