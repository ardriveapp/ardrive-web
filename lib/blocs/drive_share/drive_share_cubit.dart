import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/link_generators.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'drive_share_state.dart';

/// [DriveShareCubit] includes logic for the user to retrieve a link to share a public drive with.
class DriveShareCubit extends Cubit<DriveShareState> {
  final Drive drive;

  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;

  DriveShareCubit({
    required this.drive,
    required DriveDao driveDao,
    required ProfileCubit profileCubit,
  })  : _driveDao = driveDao,
        _profileCubit = profileCubit,
        super(DriveShareLoadInProgress()) {
    loadDriveShareDetails();
  }

  /// Builds the share link for [drive], or fails in a way the dialog can show.
  ///
  /// Everything here runs inside the guard on purpose. This method is called
  /// from the constructor body and its future is never awaited, so anything it
  /// throws becomes an unhandled asynchronous error: the cubit would stay in
  /// [DriveShareLoadInProgress] and the dialog would spin forever, which is
  /// exactly what a missing drive key used to do.
  Future<void> loadDriveShareDetails() async {
    emit(DriveShareLoadInProgress());

    try {
      final driveShareLink = drive.isPrivate
          ? await _privateDriveShareLink()
          : generatePublicDriveShareLink(
              driveId: drive.id,
              driveName: drive.name,
            );

      if (isClosed) {
        return;
      }

      emit(
        DriveShareLoadSuccess(
          drive: drive,
          driveShareLink: driveShareLink,
        ),
      );
    } catch (e, stacktrace) {
      // The drive id is safe to log; the key never is, and nothing here puts
      // one in the message.
      logger.e(
        'Failed to build the share link for drive ${drive.id}',
        e,
        stacktrace,
      );

      if (isClosed) {
        return;
      }

      emit(const DriveShareLoadFail());
    }
  }

  /// The link for a private drive, which needs the drive key to be reachable.
  ///
  /// The key comes from the profile when one is signed in, and from the
  /// in-memory store otherwise - a drive attached in this session but never
  /// persisted. Neither is guaranteed, and a [StateError] here is a real
  /// outcome rather than a should-never-happen: it lands on the failure state
  /// above.
  Future<Uri> _privateDriveShareLink() async {
    final profileState = _profileCubit.state;

    final driveKey = profileState is ProfileLoggedIn
        ? await _driveDao.getDriveKey(drive.id, profileState.user.cipherKey)
        : await _driveDao.getDriveKeyFromMemory(drive.id);

    if (driveKey == null) {
      throw StateError('Drive key not found');
    }

    return generatePrivateDriveShareLink(
      driveId: drive.id,
      driveName: drive.name,
      driveKey: driveKey.key,
    );
  }
}
