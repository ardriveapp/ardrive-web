import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:drive/blocs/blocs.dart';
import 'package:drive/repositories/entities/entities.dart';
import 'package:drive/repositories/repositories.dart';
import 'package:rxdart/rxdart.dart';

part 'drives_event.dart';
part 'drives_state.dart';

class DrivesBloc extends Bloc<DrivesEvent, DrivesState> {
  final UserBloc _userBloc;
  final SyncBloc _syncBloc;
  final ArweaveDao _arweaveDao;
  final DrivesDao _drivesDao;

  StreamSubscription _drivesSubscription;

  DrivesBloc(
      {UserBloc userBloc,
      SyncBloc syncBloc,
      ArweaveDao arweaveDao,
      DrivesDao drivesDao})
      : _userBloc = userBloc,
        _syncBloc = syncBloc,
        _arweaveDao = arweaveDao,
        _drivesDao = drivesDao,
        super(DrivesLoadInProgress()) {
    _drivesSubscription = Rx.combineLatest2(
      _drivesDao.watchAllDrives(),
      _userBloc.startWith(null),
      (drives, _) => drives,
    ).listen((drives) => add(DrivesUpdated(drives: drives)));
  }

  @override
  Stream<DrivesState> mapEventToState(DrivesEvent event) async* {
    if (event is SelectDrive) {
      yield* _mapSelectDriveToState(event);
    } else if (event is NewDrive) {
      yield* _mapNewDriveToState(event);
    } else if (event is AttachDrive) {
      yield* _mapAttachDriveToState(event);
    } else if (event is DrivesUpdated) yield* _mapDrivesUpdatedToState(event);
  }

  Stream<DrivesState> _mapSelectDriveToState(SelectDrive event) async* {
    if (state is DrivesLoadSuccess) {
      yield DrivesLoadSuccess(
        selectedDriveId: event.driveId,
        drives: (state as DrivesLoadSuccess).drives,
        canCreateNewDrive: _userBloc.state is UserAuthenticated,
      );
    }
  }

  Stream<DrivesState> _mapNewDriveToState(NewDrive event) async* {
    if (state is DrivesLoadSuccess) {
      final wallet = (_userBloc.state as UserAuthenticated).userWallet;

      final ids = await _drivesDao.createDrive(
          name: event.driveName, owner: wallet.address);

      final driveTx = await _arweaveDao.prepareDriveEntityTx(
          DriveEntity(id: ids[0], rootFolderId: ids[1]), wallet);
      final rootFolderTx = await _arweaveDao.prepareFolderEntityTx(
          FolderEntity(id: ids[1], driveId: ids[0], name: event.driveName),
          wallet);
      await _arweaveDao.batchPostTxs([driveTx, rootFolderTx]);
    }
  }

  Stream<DrivesState> _mapAttachDriveToState(AttachDrive event) async* {
    final driveEntity = await _arweaveDao.getDriveEntity(event.driveId);

    await _drivesDao.attachDrive(event.driveName, driveEntity);

    _syncBloc.add(SyncWithNetwork());
    add(SelectDrive(event.driveId));
  }

  Stream<DrivesState> _mapDrivesUpdatedToState(DrivesUpdated event) async* {
    String selectedDriveId;
    if (state is DrivesLoadSuccess &&
        (state as DrivesLoadSuccess).selectedDriveId != null) {
      selectedDriveId = (state as DrivesLoadSuccess).selectedDriveId;
    } else {
      selectedDriveId = event.drives.isNotEmpty ? event.drives.first.id : null;
    }

    yield DrivesLoadSuccess(
      selectedDriveId: selectedDriveId,
      drives: event.drives,
      canCreateNewDrive: _userBloc.state is UserAuthenticated,
    );
  }

  @override
  Future<void> close() {
    _drivesSubscription.cancel();
    return super.close();
  }
}
