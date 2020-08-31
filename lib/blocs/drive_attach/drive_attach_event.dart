part of 'drive_attach_bloc.dart';

@immutable
abstract class DriveAttachEvent {}

class AttemptDriveAttach extends DriveAttachEvent {
  final String driveId;
  final String driveName;

  AttemptDriveAttach(this.driveId, this.driveName);
}
