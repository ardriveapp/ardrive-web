import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:drive/blocs/blocs.dart';
import 'package:drive/models/models.dart';
import 'package:drive/services/services.dart';
import 'package:meta/meta.dart';

part 'drive_attach_event.dart';
part 'drive_attach_state.dart';

class DriveAttachBloc extends Bloc<DriveAttachEvent, DriveAttachState> {
  final ArweaveService _arweave;
  final DrivesDao _drivesDao;
  final SyncBloc _syncBloc;
  final DrivesBloc _drivesBloc;
  final ProfileBloc _profileBloc;

  DriveAttachBloc({
    ArweaveService arweave,
    DrivesDao drivesDao,
    SyncBloc syncBloc,
    DrivesBloc drivesBloc,
    ProfileBloc profileBloc,
  })  : _arweave = arweave,
        _drivesDao = drivesDao,
        _syncBloc = syncBloc,
        _drivesBloc = drivesBloc,
        _profileBloc = profileBloc,
        super(DriveAttachInitial());

  @override
  Stream<DriveAttachState> mapEventToState(
    DriveAttachEvent event,
  ) async* {
    if (event is AttemptDriveAttach) {
      yield* _mapAttemptDriveAttachToState(event);
    }
  }

  Stream<DriveAttachState> _mapAttemptDriveAttachToState(
      AttemptDriveAttach event) async* {
    yield DriveAttachInProgress();

    final profile = _profileBloc.state as ProfileLoaded;

    final driveKey =
        await deriveDriveKey(profile.wallet, event.driveId, profile.password);

    final driveEntity = await _arweave.getDriveEntity(event.driveId, driveKey);

    await _drivesDao.attachDrive(
      name: event.driveName,
      entity: driveEntity,
      driveKey: driveKey,
      profileKey: profile.cipherKey,
    );

    _syncBloc.add(SyncWithNetwork());
    _drivesBloc.add(SelectDrive(event.driveId));

    yield DriveAttachSuccessful();
  }
}
