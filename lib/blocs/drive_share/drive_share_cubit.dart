import 'package:ardrive/models/models.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

part 'drive_share_state.dart';

/// [DriveShareCubit] includes logic for the user to retrieve a link to share a public drive with.
class DriveShareCubit extends Cubit<DriveShareState> {
  final String driveId;

  final DriveDao _driveDao;

  DriveShareCubit({
    @required this.driveId,
    @required DriveDao driveDao,
  })  : _driveDao = driveDao,
        super(DriveShareLoadInProgress()) {
    loadDriveShareDetails();
  }
  Future<void> loadDriveShareDetails() async {
    emit(DriveShareLoadInProgress());

    final drive = await _driveDao.getDriveById(driveId);

    // On web, link to the current origin the user is on.
    // Elsewhere, link to app.ardrive.io.
    final linkOrigin = kIsWeb ? Uri.base.origin : 'https://app.ardrive.io';
    var driveShareLink = '$linkOrigin/#/drives/${drive.id}';

    emit(
      DriveShareLoadSuccess(
        driveName: drive.name,
        driveShareLink: Uri.parse(driveShareLink),
      ),
    );
  }
}
