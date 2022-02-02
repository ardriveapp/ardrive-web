import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:bloc/bloc.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

part 'drive_share_state.dart';

/// [DriveShareCubit] includes logic for the user to retrieve a link to share a public drive with.
class DriveShareCubit extends Cubit<DriveShareState> {
  final String driveId;

  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;

  DriveShareCubit({
    required this.driveId,
    required DriveDao driveDao,
    required ProfileCubit profileCubit,
  })  : _driveDao = driveDao,
        _profileCubit = profileCubit,
        super(DriveShareLoadInProgress()) {
    loadDriveShareDetails();
  }
  Future<void> loadDriveShareDetails() async {
    emit(DriveShareLoadInProgress());

    final drive = await _driveDao.driveById(driveId: driveId).getSingle();

    // On web, link to the current origin the user is on.
    // Elsewhere, link to app.ardrive.io.
    final linkOrigin = kIsWeb ? Uri.base.origin : 'https://app.ardrive.io';
    final driveName = drive.name;

    var driveShareLink = '$linkOrigin/#/drives/${drive.id}?name=' +
        Uri.encodeQueryComponent(driveName);
    if (!drive.isPublic) {
      final profile = _profileCubit.state as ProfileLoggedIn;

      final driveKey = (await _driveDao.getDriveKey(driveId, profile.cipherKey))
          as SecretKey;
      final driveKeyBase64 =
          utils.encodeBytesToBase64(await driveKey.extractBytes());

      driveShareLink = driveShareLink + '?driveKey=$driveKeyBase64';
    }
    emit(
      DriveShareLoadSuccess(
        driveName: drive.name,
        driveShareLink: Uri.parse(driveShareLink),
      ),
    );
  }
}
