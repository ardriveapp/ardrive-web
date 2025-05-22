import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/link_generators.dart';
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

  Future<void> loadDriveShareDetails() async {
    late Uri driveShareLink;
    emit(DriveShareLoadInProgress());

    if (drive.isPrivate) {
      DriveKey? driveKey;
      if (_profileCubit.state is ProfileLoggedIn) {
        final profileKey =
            (_profileCubit.state as ProfileLoggedIn).user.cipherKey;
        driveKey = await _driveDao.getDriveKey(drive.id, profileKey);
      } else {
        driveKey = await _driveDao.getDriveKeyFromMemory(drive.id);
      }
      if (driveKey != null) {
        driveShareLink = await generatePrivateDriveShareLink(
          driveId: drive.id,
          driveName: drive.name,
          driveKey: driveKey.key,
        );
      } else {
        throw StateError('Drive key not found');
      }
    } else {
      driveShareLink = generatePublicDriveShareLink(
        driveId: drive.id,
        driveName: drive.name,
      );
    }

    emit(
      DriveShareLoadSuccess(
        drive: drive,
        driveShareLink: driveShareLink,
      ),
    );
  }
}
