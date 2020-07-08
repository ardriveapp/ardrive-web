import 'package:drive/models/drive.dart';

abstract class DriveEvent {}

class DriveAddedEvent extends DriveEvent {
  Drive drive;

  DriveAddedEvent(this.drive);
}
