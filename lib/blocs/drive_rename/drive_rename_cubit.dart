import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'drive_rename_state.dart';

class DriveRenameCubit extends Cubit<DriveRenameState> {
  final String driveId;

  final ArweaveService _arweave;
  final TurboUploadService _turboUploadService;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;

  DriveRenameCubit({
    required this.driveId,
    required ArweaveService arweave,
    required TurboUploadService turboUploadService,
    required DriveDao driveDao,
    required ProfileCubit profileCubit,
    required SyncCubit syncCubit,
  })  : _arweave = arweave,
        _turboUploadService = turboUploadService,
        _driveDao = driveDao,
        _profileCubit = profileCubit,
        super(DriveRenameInitial()) {
    () async {
      emit(DriveRenameInitial());
    }();
  }

  Future<void> submit({
    required String newName,
    bool proceedIfHasConflicts = false,
  }) async {
    try {
      final profile = _profileCubit.state as ProfileLoggedIn;

      final driveKey =
          await _driveDao.getDriveKey(driveId, profile.user.cipherKey);

      if (await _profileCubit.logoutIfWalletMismatch()) {
        emit(DriveRenameWalletMismatch());
        return;
      }

      if (await _fileWithSameNameExistis(newName) && !proceedIfHasConflicts) {
        final previousState = state;
        emit(DriveNameAlreadyExists(newName));
        emit(previousState);
        return;
      }

      emit(DriveRenameInProgress());

      await _driveDao.transaction(() async {
        var drive = await _driveDao.driveById(driveId: driveId).getSingle();
        drive = drive.copyWith(name: newName, lastUpdated: DateTime.now());
        final driveEntity = drive.asEntity();

        if (_turboUploadService.useTurboUpload) {
          final driveDataItem = await _arweave.prepareEntityDataItem(
            driveEntity,
            profile.user.wallet,
            key: driveKey?.key,
          );
          await _turboUploadService.postDataItem(
            dataItem: driveDataItem,
            wallet: profile.user.wallet,
          );
          driveEntity.txId = driveDataItem.id;
        } else {
          final driveTx = await _arweave.prepareEntityTx(
            driveEntity,
            profile.user.wallet,
            driveKey?.key,
          );
          await _arweave.postTx(driveTx);
          driveEntity.txId = driveTx.id;
        }

        driveEntity.ownerAddress = profile.user.walletAddress;
        await _driveDao.writeToDrive(drive);
        await _driveDao.insertDriveRevision(driveEntity.toRevisionCompanion(
          performedAction: RevisionAction.rename,
        ));
      });

      emit(DriveRenameSuccess());
    } catch (err) {
      addError(err);
    }
  }

  Future<bool> _fileWithSameNameExistis(String newName) async {
    final drivesWithName = (await _driveDao.allDrives().get())
        .where((element) => element.name == newName);

    final nameAlreadyExists = drivesWithName.isNotEmpty;

    return nameAlreadyExists;
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(DriveRenameFailure());

    super.onError(error, stackTrace);
  }
}
