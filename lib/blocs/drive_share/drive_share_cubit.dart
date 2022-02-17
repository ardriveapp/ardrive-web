import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/link_generators.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

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

  Future<void> loadDriveShareDetails() async {
    late String driveShareLink;
    emit(DriveShareLoadInProgress());

    if (drive.isPrivate && !(_profileCubit.state is ProfileLoggedIn)) {
      // Note: Should we even show the share drive link on attached private drive?
      emit(DriveShareLoadFail(message: 'Please login to share private drive.'));
    } else if (drive.isPrivate) {
      final profileKey = (_profileCubit.state as ProfileLoggedIn).cipherKey;
      final driveKey = await _driveDao.getDriveKey(drive.id, profileKey);
      driveShareLink = await generateDriveShareLink(
        drive: drive,
        driveKey: driveKey,
      );
    } else {
      driveShareLink = await generateDriveShareLink(drive: drive);
    }

    emit(
      DriveShareLoadSuccess(
        driveName: drive.name,
        driveShareLink: Uri.parse(driveShareLink),
      ),
    );
  }
}
