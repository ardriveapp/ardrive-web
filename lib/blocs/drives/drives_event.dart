part of 'drives_bloc.dart';

abstract class DrivesEvent {}

class DriveAdded extends DrivesEvent {
  Drive drive;

  DriveAdded(this.drive);
}
