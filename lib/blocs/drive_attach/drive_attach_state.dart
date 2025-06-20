part of 'drive_attach_cubit.dart';

@immutable
abstract class DriveAttachState extends Equatable {
  @override
  List<Object> get props => [];
}

class DriveAttachInitial extends DriveAttachState {}

class DriveAttachPrivate extends DriveAttachState {}

class DriveAttachDriveNotFound extends DriveAttachState {}

class DriveAttachInProgress extends DriveAttachState {}

class DriveAttachSuccess extends DriveAttachState {}

class DriveAttachSyncing extends DriveAttachState {
  final bool hasSnapshots;
  
  DriveAttachSyncing({this.hasSnapshots = false});
  
  @override
  List<Object> get props => [hasSnapshots];
}

class DriveAttachFailure extends DriveAttachState {}

class DriveAttachInvalidDriveKey extends DriveAttachState {}
