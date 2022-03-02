part of 'drive_attach_cubit.dart';

@immutable
abstract class DriveAttachState extends Equatable {
  @override
  List<Object> get props => [];
}

class DriveAttachInitial extends DriveAttachState {}

class DriveAttachPrivate extends DriveAttachState {}

class DriveAttachPrivateNotLoggedIn extends DriveAttachState {}

class DriveAttachDriveNotFound extends DriveAttachState {}

class DriveAttachInProgress extends DriveAttachState {}

class DriveAttachSuccess extends DriveAttachState {}

class DriveAttachFailure extends DriveAttachState {}
