part of 'drive_attach_cubit.dart';

@immutable
abstract class DriveAttachState extends Equatable {
  @override
  List<Object> get props => [];
}

class DriveAttachInitial extends DriveAttachState {}

class DriveAttachInProgress extends DriveAttachState {}

class DriveAttachSuccessful extends DriveAttachState {}
