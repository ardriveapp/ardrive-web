import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:drive/blocs/user/user_bloc.dart';
import 'package:meta/meta.dart';

import '../../repositories/repositories.dart';

part 'sync_event.dart';
part 'sync_state.dart';

class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final UserBloc _userBloc;
  final ArweaveDao _arweaveDao;
  final DrivesDao _drivesDao;

  SyncBloc(
      {@required UserBloc userBloc,
      @required ArweaveDao arweaveDao,
      @required DrivesDao drivesDao})
      : _userBloc = userBloc,
        _arweaveDao = arweaveDao,
        _drivesDao = drivesDao,
        super(SyncIdle());

  @override
  Stream<SyncState> mapEventToState(
    SyncEvent event,
  ) async* {
    if (event is SyncWithNetwork) yield* _mapSyncWithNetworkToState(event);
  }

  Stream<SyncState> _mapSyncWithNetworkToState(SyncWithNetwork event) async* {
    yield SyncInProgress();

    final drives = await _drivesDao.getAllDrives();
    final driveSyncProcesses = drives.map(
      (drive) => Future.microtask(
        () async {
          final entityHistory =
              await _arweaveDao.getDriveEntityHistory(drive.id, 0);
          await _drivesDao.applyEntityHistory(drive.id, entityHistory);
        },
      ),
    );

    await Future.wait(driveSyncProcesses);

    yield SyncIdle();
  }
}
