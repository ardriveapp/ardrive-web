part of 'drive_rename_cubit.dart';

abstract class DriveRenameState extends Equatable {
  const DriveRenameState();

  @override
  List<Object> get props => [];
}

class DriveRenameInitial extends DriveRenameState {}

class DriveRenameInProgress extends DriveRenameState {}

class DriveRenameSuccess extends DriveRenameState {}

class DriveRenameFailure extends DriveRenameState {
  final bool isPaymentError;
  const DriveRenameFailure({this.isPaymentError = false});

  @override
  List<Object> get props => [isPaymentError];
}

class DriveRenameWalletMismatch extends DriveRenameState {}

class DriveNameAlreadyExists extends DriveRenameState {
  final String driveName;

  const DriveNameAlreadyExists(this.driveName);

  @override
  List<Object> get props => [driveName];
}
