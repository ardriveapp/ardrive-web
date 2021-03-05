part of 'drive_rename_cubit.dart';

abstract class DriveRenameState extends Equatable {
  const DriveRenameState();

  @override
  List<Object> get props => [];
}

class DriveRenameInitial extends DriveRenameState {}

class DriveRenameInProgress extends DriveRenameState {}

class DriveRenameSuccess extends DriveRenameState {}

class DriveRenameFailure extends DriveRenameState {}
