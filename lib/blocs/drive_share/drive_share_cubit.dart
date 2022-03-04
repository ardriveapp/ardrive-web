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
    late Uri driveShareLink;
    emit(DriveShareLoadInProgress());

    if (drive.isPrivate) {
      if (_profileCubit.state is ProfileLoggedIn) {
        final profileKey = (_profileCubit.state as ProfileLoggedIn).cipherKey;
        final driveKey = await _driveDao.getDriveKey(drive.id, profileKey);
        driveShareLink = await generateDriveShareLink(
          drive: drive,
          driveKey: driveKey,
        );
      } else {
        emit(
          DriveShareLoadFail(message: 'Please log in to share private drive.'),
        );
        return;
      }
    } else {
      driveShareLink = await generateDriveShareLink(drive: drive);
    }

    emit(
      DriveShareLoadSuccess(
        drive: drive,
        driveShareLink: driveShareLink,
      ),
    );
  }
}
