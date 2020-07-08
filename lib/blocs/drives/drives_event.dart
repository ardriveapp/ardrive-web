import 'package:drive/repositories/repositories.dart';

abstract class DrivesEvent {}

class DriveAdded extends DrivesEvent {
  Drive drive;

  DriveAdded(this.drive);
}
