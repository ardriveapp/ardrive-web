import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'ghost_fixer_state.dart';

class GhostFixerCubit extends Cubit<GhostFixerState> {
  final FolderDataTableItem ghostFolder;
  final ProfileCubit _profileCubit;

  final ArweaveService _arweave;
  final TurboUploadService _turboUploadService;
  final DriveDao _driveDao;
  final SyncCubit _syncCubit;

  StreamSubscription? _selectedFolderSubscription;

  GhostFixerCubit({
    required this.ghostFolder,
    required ProfileCubit profileCubit,
    required ArweaveService arweave,
    required TurboUploadService turboUploadService,
    required DriveDao driveDao,
    required SyncCubit syncCubit,
  })  : _profileCubit = profileCubit,
        _arweave = arweave,
        _turboUploadService = turboUploadService,
        _driveDao = driveDao,
        _syncCubit = syncCubit,
        super(GhostFixerInitial()) {
    _driveDao
        .driveById(driveId: ghostFolder.driveId)
        .getSingle()
        .then((d) => loadFolder(d.rootFolderId));
  }
  Future<void> loadParentFolder() async {
    final state = this.state as GhostFixerFolderLoadSuccess;
    if (state.viewingFolder.folder.parentFolderId != null) {
      return loadFolder(state.viewingFolder.folder.parentFolderId!);
    }
  }

  Future<void> loadFolder(String folderId) async {
    await _selectedFolderSubscription?.cancel();

    _selectedFolderSubscription = _driveDao
        .watchFolderContents(ghostFolder.driveId, folderId: folderId)
        .listen(
          (f) => emit(
            GhostFixerFolderLoadSuccess(
              viewingRootFolder: f.folder.parentFolderId == null,
              viewingFolder: f,
              movingEntryId: ghostFolder.id,
            ),
          ),
        );
  }

  Future<bool> entityNameExists({
    required String name,
    required String parentFolderId,
  }) async {
    final foldersWithName = await _driveDao
        .foldersInFolderWithName(
            driveId: ghostFolder.driveId,
            parentFolderId: parentFolderId,
            name: name)
        .get();
    final filesWithName = await _driveDao
        .filesInFolderWithName(
            driveId: ghostFolder.driveId,
            parentFolderId: parentFolderId,
            name: name)
        .get();
    return foldersWithName.isNotEmpty || filesWithName.isNotEmpty;
  }

  Future<void> submit(String folderName) async {
    try {
      final profile = _profileCubit.state as ProfileLoggedIn;
      final state = this.state as GhostFixerFolderLoadSuccess;

      final parentFolder = state.viewingFolder.folder;

      if (await _profileCubit.logoutIfWalletMismatch()) {
        emit(GhostFixerWalletMismatch());
        return;
      }

      if (await entityNameExists(
          name: folderName, parentFolderId: parentFolder.id)) {
        final state = this.state as GhostFixerFolderLoadSuccess;
        emit(GhostFixerNameConflict(name: folderName));
        emit(state);
        return;
      }

      emit(GhostFixerRepairInProgress());

      await _driveDao.transaction(() async {
        final targetDrive =
            await _driveDao.driveById(driveId: ghostFolder.driveId).getSingle();
        final targetFolder = await _driveDao
            .folderById(
              driveId: ghostFolder.driveId,
              folderId: ghostFolder.parentFolderId!,
            )
            .getSingle();

        final driveKey = targetDrive.isPrivate
            ? await _driveDao.getDriveKey(
                targetFolder.driveId, profile.cipherKey)
            : null;

        final folder = FolderEntry(
          id: ghostFolder.id,
          driveId: ghostFolder.driveId,
          name: folderName,
          parentFolderId: parentFolder.id,
          path: '${parentFolder.path}/$folderName',
          isGhost: false,
          lastUpdated: ghostFolder.lastUpdated,
          dateCreated: ghostFolder.dateCreated,
        );

        final folderEntity = folder.asEntity();
        if (_turboUploadService.useTurboUpload) {
          final folderDataItem = await _arweave.prepareEntityDataItem(
            folderEntity,
            profile.wallet,
            key: driveKey,
          );

          await _turboUploadService.postDataItem(
            dataItem: folderDataItem,
            wallet: profile.wallet,
          );
          folderEntity.txId = folderDataItem.id;
        } else {
          final folderTx = await _arweave.prepareEntityTx(
            folderEntity,
            profile.wallet,
            driveKey,
          );

          await _arweave.postTx(folderTx);
          folderEntity.txId = folderTx.id;
        }

        await _driveDao.writeToFolder(folder);

        await _driveDao.insertFolderRevision(folderEntity.toRevisionCompanion(
            performedAction: RevisionAction.create));
        final folderMap = {folder.id: folder.toCompanion(false)};
        await _syncCubit.generateFsEntryPaths(folder.driveId, folderMap, {});
      });
      emit(GhostFixerSuccess());
    } catch (err) {
      addError(err);
    }
  }

  @override
  Future<void> close() async {
    await _selectedFolderSubscription?.cancel();
    await super.close();
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(GhostFixerFailure());
    super.onError(error, stackTrace);

    logger.e('Failed to create folder', error, stackTrace);
  }
}
