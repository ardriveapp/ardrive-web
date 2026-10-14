import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/upload_entry/domain/upload_destinations.dart';

/// What pressing Upload does, decided from where the reader is.
///
/// Upload is always offered, so it always has to lead somewhere: straight to
/// the picker inside an open drive, to the drive when there is one place it
/// can go, to a choice when there are several, and to making a drive when
/// there are none.
sealed class UploadStart {
  const UploadStart();
}

/// Inside an open drive. The ordinary road, unchanged: straight to the picker.
final class UploadHere extends UploadStart {
  const UploadHere({required this.driveId, required this.folderId});

  final String driveId;
  final String folderId;
}

/// Inside a drive that is not open yet. What happens next comes from that
/// drive's own state: a sync it needs, or the wait while it opens.
final class UploadWhenOpen extends UploadStart {
  const UploadWhenOpen({required this.driveId});

  final String driveId;
}

/// No drive to upload to, so one has to be made first.
final class UploadNeedsDrive extends UploadStart {
  const UploadNeedsDrive();
}

/// One place it can go. Opening that drive is the whole choice.
final class UploadIntoDrive extends UploadStart {
  const UploadIntoDrive(this.drive);

  final Drive drive;
}

/// Several places it can go, in the order to offer them.
final class UploadChooseDrive extends UploadStart {
  const UploadChooseDrive(this.drives);

  final List<Drive> drives;
}

/// The drives are not known yet, so nothing can be offered truthfully.
final class UploadNotYet extends UploadStart {
  const UploadNotYet();
}

/// Decides [UploadStart].
///
/// [openDriveId] is the drive the explorer is showing, or [rootPath] when it
/// is showing none. [showingDrivesList] wins over the explorer's state: the
/// cubit the drives list provides is built against no drive, and what it
/// reports says nothing about where the reader is.
UploadStart decideUploadStart({
  required DriveDetailState detailState,
  required bool showingDrivesList,
  required String? openDriveId,
  required DrivesState drivesState,
}) {
  if (!showingDrivesList) {
    if (detailState is DriveDetailLoadSuccess) {
      return UploadHere(
        driveId: detailState.currentDrive.id,
        folderId: detailState.folderInView.folder.id,
      );
    }

    if (detailState is DriveDetailLoadUnsynced) {
      return UploadWhenOpen(driveId: detailState.drive.id);
    }

    final isOpening = detailState is DriveDetailLoadInProgress ||
        detailState is DriveInitialLoading;

    if (isOpening && openDriveId != null && openDriveId != rootPath) {
      return UploadWhenOpen(driveId: openDriveId);
    }
  }

  if (drivesState is! DrivesLoadSuccess) {
    return const UploadNotYet();
  }

  final destinations = uploadDestinations(
    ownedDrives: drivesState.userDrives,
    lastSelectedDriveId: drivesState.selectedDriveId,
  );

  if (destinations.isEmpty) {
    return const UploadNeedsDrive();
  }

  if (destinations.length == 1) {
    return UploadIntoDrive(destinations.single);
  }

  return UploadChooseDrive(destinations);
}
