import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:drive/blocs/blocs.dart';
import 'package:drive/repositories/repositories.dart';
import 'package:meta/meta.dart';

part 'drive_attach_event.dart';
part 'drive_attach_state.dart';

class DriveAttachBloc extends Bloc<DriveAttachEvent, DriveAttachState> {
  final ArweaveDao _arweaveDao;
  final DrivesDao _drivesDao;
  final SyncBloc _syncBloc;
  final DrivesBloc _drivesBloc;
  final UserBloc _userBloc;

  DriveAttachBloc({
    ArweaveDao arweaveDao,
    DrivesDao drivesDao,
    SyncBloc syncBloc,
    DrivesBloc drivesBloc,
    UserBloc userBloc,
  })  : _arweaveDao = arweaveDao,
        _drivesDao = drivesDao,
        _syncBloc = syncBloc,
        _drivesBloc = drivesBloc,
        _userBloc = userBloc,
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

    final wallet = (_userBloc.state as UserAuthenticated).userWallet;
    final driveEntity = await _arweaveDao.getDriveEntity(event.driveId, wallet);

    await _drivesDao.attachDrive(event.driveName, driveEntity);

    _syncBloc.add(SyncWithNetwork());
    _drivesBloc.add(SelectDrive(event.driveId));

    yield DriveAttachSuccessful();
  }
}
