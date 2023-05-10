import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'drive_create_state.dart';

class DriveCreateCubit extends Cubit<DriveCreateState> {
  final form = FormGroup({
    'privacy': FormControl<String>(
        value: DrivePrivacy.private, validators: [Validators.required]),
  });

  final ArweaveService _arweave;
  final UploadService _turboUploadService;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final DrivesCubit _drivesCubit;

  DriveCreateCubit({
    required ArweaveService arweave,
    required UploadService turboUploadService,
    required DriveDao driveDao,
    required ProfileCubit profileCubit,
    required DrivesCubit drivesCubit,
  })  : _arweave = arweave,
        _turboUploadService = turboUploadService,
        _driveDao = driveDao,
        _profileCubit = profileCubit,
        _drivesCubit = drivesCubit,
        super(DriveCreateInitial());

  Future<void> submit(
    String driveName,
  ) async {
    final profile = _profileCubit.state as ProfileLoggedIn;
    if (await _profileCubit.logoutIfWalletMismatch()) {
      emit(DriveCreateWalletMismatch());
      return;
    }

    final minimumWalletBalance = BigInt.from(10000000);
    if (profile.walletBalance <= minimumWalletBalance &&
        !_turboUploadService.useTurbo) {
      emit(DriveCreateZeroBalance());
      return;
    }

    emit(DriveCreateInProgress());

    try {
      final String drivePrivacy = form.control('privacy').value;
      final walletAddress = await profile.wallet.getAddress();
      final createRes = await _driveDao.createDrive(
        name: driveName,
        ownerAddress: walletAddress,
        privacy: drivePrivacy,
        wallet: profile.wallet,
        password: profile.password,
        profileKey: profile.cipherKey,
      );

      final drive = DriveEntity(
        id: createRes.driveId,
        name: driveName,
        rootFolderId: createRes.rootFolderId,
        privacy: drivePrivacy,
        authMode: drivePrivacy == DrivePrivacy.private
            ? DriveAuthMode.password
            : null,
      );

      final driveDataItem = await _arweave.prepareEntityDataItem(
        drive,
        profile.wallet,
        key: createRes.driveKey,
      );

      final rootFolderEntity = FolderEntity(
        id: drive.rootFolderId,
        driveId: drive.id,
        name: driveName,
      );

      final rootFolderDataItem = await _arweave.prepareEntityDataItem(
        rootFolderEntity,
        profile.wallet,
        key: createRes.driveKey,
      );

      await rootFolderDataItem.sign(profile.wallet);
      await driveDataItem.sign(profile.wallet);
      late TransactionBase createTx;
      if (_turboUploadService.useTurbo) {
        createTx = await _arweave.prepareBundledDataItem(
          await DataBundle.fromDataItems(
            items: [driveDataItem, rootFolderDataItem],
          ),
          profile.wallet,
        );
        await _turboUploadService.postDataItem(dataItem: createTx as DataItem);
      } else {
        createTx = await _arweave.prepareDataBundleTx(
          await DataBundle.fromDataItems(
            items: [driveDataItem, rootFolderDataItem],
          ),
          profile.wallet,
        );
        await _arweave.postTx(createTx as Transaction);
      }

      rootFolderEntity.txId = rootFolderDataItem.id;
      await _driveDao.insertFolderRevision(rootFolderEntity.toRevisionCompanion(
          performedAction: RevisionAction.create));

      // Update drive with bundledIn
      // Creates a drive revision immediately after creation
      // so there is no more pending state in the info panel when waiting for sync to
      // pick up the drive

      drive
        ..ownerAddress = walletAddress
        ..bundledIn = createTx.id
        ..txId = driveDataItem.id;

      await _driveDao.insertDriveRevision(
          drive.toRevisionCompanion(performedAction: RevisionAction.create));
      _drivesCubit.selectDrive(drive.id!);
    } catch (err) {
      addError(err);
    }

    emit(DriveCreateSuccess());
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(DriveCreateFailure());
    super.onError(error, stackTrace);

    print('Failed to create drive: $error $stackTrace');
  }
}
