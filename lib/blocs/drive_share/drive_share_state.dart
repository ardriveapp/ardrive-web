part of 'drive_share_cubit.dart';

@immutable
abstract class DriveShareState extends Equatable {
  const DriveShareState();

  @override
  List<Object> get props => [];
}

/// [DriveShareLoadInProgress] means that the drive share details are being loaded.
class DriveShareLoadInProgress extends DriveShareState {}

/// [DriveShareLoadSuccess] provides details for the user to share the drive with.
class DriveShareLoadSuccess extends DriveShareState {
  final String driveName;

  /// The link to share access of this drive with.
  final Uri driveShareLink;

  DriveShareLoadSuccess({
    required this.driveName,
    required this.driveShareLink,
  });

  @override
  List<Object> get props => [driveName, driveShareLink];
}

class DriveShareLoadFail extends DriveShareState {
  final String message;

  DriveShareLoadFail({
    required this.message,
  });

  @override
  List<Object> get props => [message];
}
