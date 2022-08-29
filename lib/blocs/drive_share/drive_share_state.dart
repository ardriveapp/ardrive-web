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
  final Drive drive;

  /// The link to share access of this drive with.
  final Uri driveShareLink;

  const DriveShareLoadSuccess({
    required this.drive,
    required this.driveShareLink,
  });

  @override
  List<Object> get props => [drive, driveShareLink];
}

/// [DriveShareLoadFail] shows failiure states in the UI.
class DriveShareLoadFail extends DriveShareState {
  final String message;

  const DriveShareLoadFail({
    required this.message,
  });

  @override
  List<Object> get props => [message];
}
