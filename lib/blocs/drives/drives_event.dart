part of 'drives_bloc.dart';

abstract class DrivesEvent extends Equatable {
  @override
  List<Object> get props => [];
}

class SelectDrive extends DrivesEvent {
  final String driveId;

  SelectDrive(this.driveId);

  @override
  List<Object> get props => [driveId];
}

class NewDrive extends DrivesEvent {
  final String driveName;
  final String drivePrivacy;

  NewDrive(this.driveName, this.drivePrivacy);

  @override
  List<Object> get props => [driveName, drivePrivacy];
}

class DrivesUpdated extends DrivesEvent {
  final List<Drive> drives;

  DrivesUpdated({this.drives});
}
