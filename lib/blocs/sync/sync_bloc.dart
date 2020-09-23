import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:drive/entities/entities.dart';
import 'package:drive/models/models.dart';
import 'package:drive/services/services.dart';
import 'package:meta/meta.dart';

import '../blocs.dart';

part 'sync_event.dart';
part 'sync_state.dart';

class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final ProfileBloc _profileBloc;
  final ArweaveService _arweave;
  final DrivesDao _drivesDao;
  final DriveDao _driveDao;

  SyncBloc({
    @required ProfileBloc profileBloc,
    @required ArweaveService arweave,
    @required DrivesDao drivesDao,
    @required DriveDao driveDao,
  })  : _profileBloc = profileBloc,
        _arweave = arweave,
        _drivesDao = drivesDao,
        _driveDao = driveDao,
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

    if (_profileBloc.state is ProfileActive) {
      final profile = _profileBloc.state as ProfileActive;

      final drives = await _drivesDao.getAllDrives();

      final driveSyncProcesses = drives.map(
        (drive) => Future.microtask(
          () async {
            final driveKey = drive.privacy == DrivePrivacy.private
                ? await _driveDao.getDriveKey(drive.id, profile.cipherKey)
                : null;

            final history = await _arweave.getDriveEntityHistory(
              drive.id,
              drive.latestSyncedBlock,
              driveKey,
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
