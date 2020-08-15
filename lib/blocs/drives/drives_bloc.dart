import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:drive/repositories/repositories.dart';

part 'drives_event.dart';
part 'drives_state.dart';

class DrivesBloc extends Bloc<DrivesEvent, DrivesState> {
  final DrivesDao _drivesDao;
  StreamSubscription _drivesSubscription;

  DrivesBloc({DrivesDao drivesDao})
      : this._drivesDao = drivesDao,
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

  Stream<DrivesState> _mapDrivesUpdatedToState(DrivesUpdated event) async* {
    yield DrivesReady(selectedDriveId: state is DrivesReady ? (state as DrivesReady).selectedDriveId : null, drives: event.drives);
  }
}
