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
    else if (event is AddDrive)
      yield* _mapAddDriveToState(event);
    else if (event is DrivesUpdated) yield* _mapUpdateDrivesToState(event);
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

  Stream<DrivesState> _mapAddDriveToState(AddDrive event) async* {
    if (state is DrivesReady) {
      this._drivesDao.createDrive(name: 'Work');
    }
  }

  Stream<DrivesState> _mapUpdateDrivesToState(DrivesUpdated event) async* {
    yield DrivesReady(drives: event.drives);
  }
}
