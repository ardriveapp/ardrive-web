import 'package:ardrive/blocs/hide/hide_event.dart';
import 'package:ardrive/blocs/hide/hide_state.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class HideBloc extends Bloc<HideEvent, HideState> {
  final ArweaveService _arweave;
  final ArDriveCrypto _crypto;
  final TurboUploadService _turboUploadService;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;

  HideBloc({
    required ArweaveService arweaveService,
    required ArDriveCrypto crypto,
    required TurboUploadService turboUploadService,
    required DriveDao driveDao,
    required ProfileCubit profileCubit,
  })  : _arweave = arweaveService,
        _crypto = crypto,
        _turboUploadService = turboUploadService,
        _driveDao = driveDao,
        _profileCubit = profileCubit,
        super(const InitialHideState()) {
    on<HideFileEvent>(_onHideFileEvent);
    on<HideFolderEvent>(_onHideFolderEvent);
    on<UnhideFileEvent>(_onUnhideFileEvent);
    on<UnhideFolderEvent>(_onUnhideFolderEvent);
  }

  Future<void> _onHideFileEvent(
    HideFileEvent event,
    Emitter<HideState> emit,
  ) async {
    final profile = _profileCubit.state as ProfileLoggedIn;
    late DataItem fileDataItem;

    await _driveDao.transaction(() async {
      final FileEntry currentFile = await _driveDao
          .fileById(
            driveId: event.driveId,
            fileId: event.fileId,
          )
          .getSingle();
      final newFile = currentFile.copyWith(
        isHidden: true,
        lastUpdated: DateTime.now(),
      );
      final fileEntity = newFile.asEntity();

      final driveKey = await _driveDao.getDriveKey(
        event.driveId,
        profile.cipherKey,
      );
      final fileKey = driveKey != null
          ? await _crypto.deriveFileKey(driveKey, currentFile.id)
          : null;
      fileDataItem = await _arweave.prepareEntityDataItem(
        fileEntity,
        profile.wallet,
        key: fileKey,
      );

      await _driveDao.writeToFile(newFile);
      fileEntity.txId = fileDataItem.id;

      await _driveDao.insertFileRevision(fileEntity.toRevisionCompanion(
        performedAction: RevisionAction.hide,
      ));

      logger.d(
        'Hiding file ${event.fileId} in drive ${event.driveId}'
        ' with JSON: ${fileEntity.toJson()}',
      );

      if (_turboUploadService.useTurboUpload) {
        await _turboUploadService.postDataItem(
          dataItem: fileDataItem,
          wallet: profile.wallet,
        );
      } else {
        final hideTx = await _arweave.prepareDataBundleTx(
          await DataBundle.fromDataItems(items: [fileDataItem]),
          profile.wallet,
        );
        await _arweave.postTx(hideTx);
      }
    });

    // event.onDone();
  }

  Future<void> _onHideFolderEvent(
    HideFolderEvent event,
    Emitter<HideState> emit,
  ) async {
    logger.d('Hiding folder ${event.folderId} in drive ${event.driveId}');
    final profile = _profileCubit.state as ProfileLoggedIn;
    late DataItem folderDataItem;

    await _driveDao.transaction(() async {
      final FolderEntry currentFolder = await _driveDao
          .folderById(
            driveId: event.driveId,
            folderId: event.folderId,
          )
          .getSingle();
      final newFolder = currentFolder.copyWith(
        isHidden: true,
        lastUpdated: DateTime.now(),
      );
      final folderEntity = newFolder.asEntity();

      final driveKey = await _driveDao.getDriveKey(
        event.driveId,
        profile.cipherKey,
      );
      final folderKey = driveKey;
      folderDataItem = await _arweave.prepareEntityDataItem(
        folderEntity,
        profile.wallet,
        key: folderKey,
      );

      await _driveDao.writeToFolder(newFolder);
      folderEntity.txId = folderDataItem.id;

      await _driveDao.insertFolderRevision(folderEntity.toRevisionCompanion(
        performedAction: RevisionAction.hide,
      ));

      logger.d(
        'Hiding folder ${event.folderId} in drive ${event.driveId}'
        ' with JSON: ${folderEntity.toJson()}',
      );

      if (_turboUploadService.useTurboUpload) {
        await _turboUploadService.postDataItem(
          dataItem: folderDataItem,
          wallet: profile.wallet,
        );
      } else {
        final hideTx = await _arweave.prepareDataBundleTx(
          await DataBundle.fromDataItems(items: [folderDataItem]),
          profile.wallet,
        );
        await _arweave.postTx(hideTx);
      }
    });

    // event.onDone();
  }

  Future<void> _onUnhideFileEvent(
    UnhideFileEvent event,
    Emitter<HideState> emit,
  ) async {
    final profile = _profileCubit.state as ProfileLoggedIn;
    late DataItem fileDataItem;

    await _driveDao.transaction(() async {
      final FileEntry currentFile = await _driveDao
          .fileById(
            driveId: event.driveId,
            fileId: event.fileId,
          )
          .getSingle();
      final newFile = currentFile.copyWith(
        isHidden: false,
        lastUpdated: DateTime.now(),
      );
      final fileEntity = newFile.asEntity();

      final driveKey = await _driveDao.getDriveKey(
        event.driveId,
        profile.cipherKey,
      );
      final fileKey = driveKey != null
          ? await _crypto.deriveFileKey(driveKey, currentFile.id)
          : null;
      fileDataItem = await _arweave.prepareEntityDataItem(
        fileEntity,
        profile.wallet,
        key: fileKey,
      );

      await _driveDao.writeToFile(newFile);
      fileEntity.txId = fileDataItem.id;

      await _driveDao.insertFileRevision(fileEntity.toRevisionCompanion(
        performedAction: RevisionAction.unhide,
      ));

      if (_turboUploadService.useTurboUpload) {
        await _turboUploadService.postDataItem(
          dataItem: fileDataItem,
          wallet: profile.wallet,
        );
      } else {
        final hideTx = await _arweave.prepareDataBundleTx(
          await DataBundle.fromDataItems(items: [fileDataItem]),
          profile.wallet,
        );
        await _arweave.postTx(hideTx);
      }
    });

    // event.onDone();
  }

  Future<void> _onUnhideFolderEvent(
    UnhideFolderEvent event,
    Emitter<HideState> emit,
  ) async {
    logger.d('Unhiding folder ${event.folderId} in drive ${event.driveId}');
    final profile = _profileCubit.state as ProfileLoggedIn;
    late DataItem folderDataItem;

    await _driveDao.transaction(() async {
      final FolderEntry currentFolder = await _driveDao
          .folderById(
            driveId: event.driveId,
            folderId: event.folderId,
          )
          .getSingle();
      final newFolder = currentFolder.copyWith(
        isHidden: false,
        lastUpdated: DateTime.now(),
      );
      final folderEntity = newFolder.asEntity();

      final driveKey = await _driveDao.getDriveKey(
        event.driveId,
        profile.cipherKey,
      );
      final folderKey = driveKey;
      folderDataItem = await _arweave.prepareEntityDataItem(
        folderEntity,
        profile.wallet,
        key: folderKey,
      );

      await _driveDao.writeToFolder(newFolder);
      folderEntity.txId = folderDataItem.id;

      await _driveDao.insertFolderRevision(folderEntity.toRevisionCompanion(
        performedAction: RevisionAction.unhide,
      ));

      if (_turboUploadService.useTurboUpload) {
        await _turboUploadService.postDataItem(
          dataItem: folderDataItem,
          wallet: profile.wallet,
        );
      } else {
        final hideTx = await _arweave.prepareDataBundleTx(
          await DataBundle.fromDataItems(items: [folderDataItem]),
          profile.wallet,
        );
        await _arweave.postTx(hideTx);
      }
    });

    // event.onDone();
  }
}
