import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:drive/entities/entities.dart';
import 'package:drive/models/models.dart';
import 'package:drive/services/services.dart';
import 'package:rxdart/rxdart.dart';

import '../blocs.dart';

part 'drives_state.dart';

class DrivesCubit extends Cubit<DrivesState> {
  final ProfileBloc _profileBloc;
  final ArweaveService _arweave;
  final DrivesDao _drivesDao;

  StreamSubscription _drivesSubscription;

  DrivesCubit(
      {ProfileBloc profileBloc, ArweaveService arweave, DrivesDao drivesDao})
      : _profileBloc = profileBloc,
        _arweave = arweave,
        _drivesDao = drivesDao,
        super(DrivesLoadInProgress()) {
    _drivesSubscription = Rx.combineLatest2(
      _drivesDao.watchAllDrives(),
      _profileBloc.startWith(null),
      (drives, _) => drives,
    ).listen((drives) {
      final state = this.state;

      String selectedDriveId;
      if (state is DrivesLoadSuccess && state.selectedDriveId != null) {
        selectedDriveId = state.selectedDriveId;
      } else {
        selectedDriveId = drives.isNotEmpty ? drives.first.id : null;
      }

      emit(
        DrivesLoadSuccess(
          selectedDriveId: selectedDriveId,
          drives: drives,
          canCreateNewDrive: _profileBloc.state is ProfileLoaded,
        ),
      );
    });
  }

  void selectDrive(String driveId) {
    if (state is DrivesLoadSuccess) {
      emit((state as DrivesLoadSuccess).copyWith(selectedDriveId: driveId));
    }
  }

  void createNewDrive(String driveName, String drivePrivacy) async {
    final profile = _profileBloc.state as ProfileLoaded;
    final wallet = profile.wallet;

    final createRes = await _drivesDao.createDrive(
      name: driveName,
      ownerAddress: wallet.address,
      privacy: drivePrivacy,
      wallet: wallet,
      password: profile.password,
      profileKey: profile.cipherKey,
    );

    final drive = DriveEntity(
      id: createRes.driveId,
      name: driveName,
      rootFolderId: createRes.rootFolderId,
      privacy: drivePrivacy,
      authMode:
          drivePrivacy == DrivePrivacy.private ? DriveAuthMode.password : null,
    );

    final driveTx =
        await _arweave.prepareEntityTx(drive, wallet, createRes.driveKey);

    final rootFolderTx = await _arweave.prepareEntityTx(
      FolderEntity(
        id: drive.rootFolderId,
        driveId: drive.id,
        name: driveName,
      ),
      wallet,
      createRes.driveKey,
    );

    await _arweave.batchPostTxs([driveTx, rootFolderTx]);
  }

  @override
  Future<void> close() {
    _drivesSubscription.cancel();
    return super.close();
  }
}
