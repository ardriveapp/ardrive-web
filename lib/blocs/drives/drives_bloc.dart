import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:drive/entities/entities.dart';
import 'package:drive/models/models.dart';
import 'package:drive/services/services.dart';
import 'package:equatable/equatable.dart';
import 'package:rxdart/rxdart.dart';

import '../blocs.dart';

part 'drives_event.dart';
part 'drives_state.dart';

class DrivesBloc extends Bloc<DrivesEvent, DrivesState> {
  final ProfileBloc _profileBloc;
  final SyncBloc _syncBloc;
  final ArweaveService _arweave;
  final DrivesDao _drivesDao;

  StreamSubscription _drivesSubscription;

  DrivesBloc(
      {ProfileBloc profileBloc,
      SyncBloc syncBloc,
      ArweaveService arweave,
      DrivesDao drivesDao})
      : _profileBloc = profileBloc,
        _syncBloc = syncBloc,
        _arweave = arweave,
        _drivesDao = drivesDao,
        super(DrivesLoadInProgress()) {
    _drivesSubscription = Rx.combineLatest2(
      _drivesDao.watchAllDrives(),
      _profileBloc.startWith(null),
      (drives, _) => drives,
    ).listen((drives) => add(DrivesUpdated(drives: drives)));
  }

  @override
  Stream<DrivesState> mapEventToState(DrivesEvent event) async* {
    if (event is SelectDrive) {
      yield* _mapSelectDriveToState(event);
    } else if (event is NewDrive) {
      yield* _mapNewDriveToState(event);
    } else if (event is DrivesUpdated) yield* _mapDrivesUpdatedToState(event);
  }

  Stream<DrivesState> _mapSelectDriveToState(SelectDrive event) async* {
    if (state is DrivesLoadSuccess) {
      yield DrivesLoadSuccess(
        selectedDriveId: event.driveId,
        drives: (state as DrivesLoadSuccess).drives,
        canCreateNewDrive: _profileBloc.state is ProfileLoaded,
      );
    }
  }

  Stream<DrivesState> _mapNewDriveToState(NewDrive event) async* {
    if (state is DrivesLoadSuccess) {
      final profile = _profileBloc.state as ProfileLoaded;
      final wallet = profile.wallet;

      final createRes = await _drivesDao.createDrive(
        name: event.driveName,
        ownerAddress: wallet.address,
        privacy: event.drivePrivacy,
        wallet: wallet,
        password: profile.password,
        profileKey: profile.cipherKey,
      );

      final drive = DriveEntity(
        id: createRes.driveId,
        name: event.driveName,
        rootFolderId: createRes.rootFolderId,
        privacy: event.drivePrivacy,
        authMode: event.drivePrivacy == DrivePrivacy.private
            ? DriveAuthMode.password
            : null,
      );

      final driveTx =
          await _arweave.prepareEntityTx(drive, wallet, createRes.driveKey);

      final rootFolderTx = await _arweave.prepareEntityTx(
        FolderEntity(
          id: drive.rootFolderId,
          driveId: drive.id,
          name: event.driveName,
        ),
        wallet,
        createRes.driveKey,
      );

      await _arweave.batchPostTxs([driveTx, rootFolderTx]);
    }
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
      canCreateNewDrive: _profileBloc.state is ProfileLoaded,
    );
  }

  @override
  Future<void> close() {
    _drivesSubscription.cancel();
    return super.close();
  }
}
