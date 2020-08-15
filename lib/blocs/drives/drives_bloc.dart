import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:drive/blocs/sync/sync_bloc.dart';
import 'package:drive/repositories/repositories.dart';

part 'drives_event.dart';
part 'drives_state.dart';

class DrivesBloc extends Bloc<DrivesEvent, DrivesState> {
  final SyncBloc _syncBloc;
  final ArweaveDao _arweaveDao;
  final DrivesDao _drivesDao;
  StreamSubscription _drivesSubscription;

  DrivesBloc({SyncBloc syncBloc, ArweaveDao arweaveDao, DrivesDao drivesDao})
      : _syncBloc = syncBloc,
        _arweaveDao = arweaveDao,
        _drivesDao = drivesDao,
        super(DrivesLoading()) {
    add(RefreshDrives());
  }

  @override
  Stream<DrivesState> mapEventToState(DrivesEvent event) async* {
    if (event is RefreshDrives)
      yield* _mapRefreshDrivesToState(event);
    else if (event is SelectDrive)
      yield* _mapSelectDriveToState(event);
    else if (event is NewDrive)
      yield* _mapNewDriveToState(event);
    else if (event is AttachDrive)
      yield* _mapAttachDriveToState(event);
    else if (event is DrivesUpdated) yield* _mapDrivesUpdatedToState(event);
  }

  Stream<DrivesState> _mapRefreshDrivesToState(RefreshDrives event) async* {
    _drivesSubscription?.cancel();
    _drivesSubscription = _drivesDao.watchAllDrives().listen(
          (drives) => add(DrivesUpdated(drives: drives)),
        );
  }

  Stream<DrivesState> _mapSelectDriveToState(SelectDrive event) async* {
    if (state is DrivesReady) {
      yield DrivesReady(
        selectedDriveId: event.driveId,
        drives: (state as DrivesReady).drives,
      );
    }
  }

  Stream<DrivesState> _mapNewDriveToState(NewDrive event) async* {
    if (state is DrivesReady) {
      this._drivesDao.createDrive(name: event.driveName);
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
    if (state is DrivesReady && (state as DrivesReady).selectedDriveId != null)
      selectedDriveId = (state as DrivesReady).selectedDriveId;
    else
      selectedDriveId = event.drives.length > 0 ? event.drives[0].id : null;

    yield DrivesReady(selectedDriveId: selectedDriveId, drives: event.drives);
  }
}
