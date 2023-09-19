part of 'drive_create_cubit.dart';

@immutable
abstract class DriveCreateState extends Equatable {
  @override
  List<Object> get props => [];
}

class DriveCreateInitial extends DriveCreateState {
  final DrivePrivacy privacy;

  DriveCreateInitial({required this.privacy});

  DriveCreateInitial copyWith({DrivePrivacy? privacy}) {
    return DriveCreateInitial(privacy: privacy ?? this.privacy);
  }

  @override
  List<Object> get props => [privacy];
}

class DriveCreateZeroBalance extends DriveCreateState {}

class DriveCreateInProgress extends DriveCreateState {}

class DriveCreateSuccess extends DriveCreateState {}

class DriveCreateFailure extends DriveCreateState {}

class DriveCreateWalletMismatch extends DriveCreateState {}
