import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart'
    show DrivePrivacy;
import 'package:ardrive/entities/drive_entity.dart';
import 'package:ardrive/entities/folder_entity.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'drive_create_state.dart';

class DriveCreateCubit extends Cubit<DriveCreateState> {
  final form = FormGroup({
    'privacy': FormControl<String>(
        value: DrivePrivacyTag.private, validators: [Validators.required]),
  });

  final ArweaveService _arweave;
  final TurboUploadService _turboUploadService;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final DrivesCubit _drivesCubit;
  final DrivePrivacy privacy;

  DriveCreateCubit({
    required ArweaveService arweave,
    required TurboUploadService turboUploadService,
    required DriveDao driveDao,
    required ProfileCubit profileCubit,
    required DrivesCubit drivesCubit,
    this.privacy = DrivePrivacy.private,
  })  : _arweave = arweave,
        _turboUploadService = turboUploadService,
        _driveDao = driveDao,
        _profileCubit = profileCubit,
        _drivesCubit = drivesCubit,
        super(DriveCreateInitial(privacy: privacy)) {
    form.control('privacy').value = privacy.name;
  }

  void onPrivacyChanged() {
    final privacy = form.control('privacy').value == DrivePrivacy.private.name
        ? DrivePrivacy.private
        : DrivePrivacy.public;
    emit(state.copyWith(privacy: privacy));
  }

  Future<void> submit(
    String driveName,
  ) async {
    final profile = _profileCubit.state as ProfileLoggedIn;
    if (await _profileCubit.logoutIfWalletMismatch()) {
      emit(DriveCreateWalletMismatch(privacy: state.privacy));
      return;
    }

    final minimumWalletBalance = BigInt.from(10000000);
    if (profile.user.walletBalance <= minimumWalletBalance &&
        !_turboUploadService.useTurboUpload) {
      emit(DriveCreateZeroBalance(privacy: state.privacy));
      return;
    }

    emit(DriveCreateInProgress(privacy: state.privacy));

    try {
      final String drivePrivacy = form.control('privacy').value;
      final walletAddress = await profile.user.wallet.getAddress();

      final createRes = await _driveDao.createDrive(
        name: driveName,
        ownerAddress: walletAddress,
        privacy: drivePrivacy,
        wallet: profile.user.wallet,
        password: profile.user.password,
        profileKey: profile.user.cipherKey,
        signatureType: drivePrivacy == DrivePrivacyTag.private ? '2' : null,
      );

      final drive = DriveEntity(
        id: createRes.driveId,
        name: driveName,
        rootFolderId: createRes.rootFolderId,
        privacy: drivePrivacy,
        authMode: drivePrivacy == DrivePrivacyTag.private
            ? DriveAuthModeTag.password
            : null,
        signatureType: drivePrivacy == DrivePrivacyTag.private ? '2' : null,
      );

      final driveDataItem = await _arweave.prepareEntityDataItem(
        drive,
        profile.user.wallet,
        key: createRes.driveKey,
      );

      final rootFolderEntity = FolderEntity(
        id: drive.rootFolderId,
        driveId: drive.id,
        name: driveName,
      );

      final rootFolderDataItem = await _arweave.prepareEntityDataItem(
        rootFolderEntity,
        profile.user.wallet,
        key: createRes.driveKey,
      );

      final signer = ArweaveSigner(profile.user.wallet);

      await rootFolderDataItem.sign(signer);
      await driveDataItem.sign(signer);
      late TransactionBase createTx;
      if (_turboUploadService.useTurboUpload) {
        createTx = await _arweave.prepareBundledDataItem(
          await DataBundle.fromDataItems(
            items: [driveDataItem, rootFolderDataItem],
          ),
          profile.user.wallet,
        );
        await _turboUploadService.postDataItem(
          dataItem: createTx as DataItem,
          wallet: profile.user.wallet,
        );
      } else {
        createTx = await _arweave.prepareDataBundleTx(
          await DataBundle.fromDataItems(
            items: [driveDataItem, rootFolderDataItem],
          ),
          profile.user.wallet,
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

    emit(DriveCreateSuccess(privacy: state.privacy));
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(DriveCreateFailure(privacy: state.privacy));
    super.onError(error, stackTrace);

    logger.e('Failed to create drive', error, stackTrace);
  }
}
