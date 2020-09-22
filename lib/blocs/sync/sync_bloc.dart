import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:drive/repositories/repositories.dart';
import 'package:meta/meta.dart';

import '../blocs.dart';

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
        super(SyncIdle()) {
    add(SyncWithNetwork());
  }

  @override
  Stream<SyncState> mapEventToState(
    SyncEvent event,
  ) async* {
    if (event is SyncWithNetwork) yield* _mapSyncWithNetworkToState(event);
  }

  Stream<SyncState> _mapSyncWithNetworkToState(SyncWithNetwork event) async* {
    yield SyncInProgress();

    if (_userBloc.state is UserAuthenticated) {
      final wallet = (_userBloc.state as UserAuthenticated).userWallet;

      final drives = await _drivesDao.getAllDrives();
      final driveSyncProcesses = drives.map(
        (drive) => Future.microtask(
          () async {
            final history = await _arweaveDao.getDriveEntityHistory(
              drive.id,
              drive.latestSyncedBlock,
              await deriveDriveKey(wallet, drive.id, 'A?WgmN8gF%H9>A/~'),
            );
            await _drivesDao.applyEntityHistory(drive.id, history);
          },
        ),
      );

      await Future.wait(driveSyncProcesses);
    }

    yield SyncIdle();
  }
}
