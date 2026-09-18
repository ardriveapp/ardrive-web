import 'package:equatable/equatable.dart';

/// An upload somebody asked for before the drive it goes to was open.
///
/// It lives only as long as that drive takes to open. An upload waiting on a
/// sync is dropped instead: see [DriveWait].
///
/// An upload can only start from inside a loaded drive: `promptToUpload` reads
/// the explorer's own `DriveDetailCubit`, and the one the drives list provides
/// is built against no drive at all. So the request is held by the router and
/// honoured by the explorer once that drive has loaded, the same road
/// `AppRouterDelegate.requestDriveInfo` takes.
class UploadRequest extends Equatable {
  const UploadRequest({
    required this.driveId,
    required this.isFolderUpload,
  });

  final String driveId;

  /// Whether the reader asked for a folder rather than files. The two open
  /// different pickers, so the choice has to survive the trip.
  final bool isFolderUpload;

  @override
  List<Object?> get props => [driveId, isFolderUpload];
}
