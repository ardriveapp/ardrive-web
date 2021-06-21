part of 'drive_create_cubit.dart';

@immutable
abstract class DriveCreateState extends Equatable {
  @override
  List<Object> get props => [];
}

class DriveCreateInitial extends DriveCreateState {}

class DriveCreateZeroBalance extends DriveCreateState {}

class DriveCreateInProgress extends DriveCreateState {}

class DriveCreateSuccess extends DriveCreateState {}

class DriveCreateFailure extends DriveCreateState {}

class DriveCreateWalletMismatch extends DriveCreateState {}
