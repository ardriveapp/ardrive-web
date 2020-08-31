part of 'drive_attach_bloc.dart';

@immutable
abstract class DriveAttachState {}

class DriveAttachInitial extends DriveAttachState {}

class DriveAttachInProgress extends DriveAttachState {}

class DriveAttachSuccessful extends DriveAttachState {}
