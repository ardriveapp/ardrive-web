import 'dart:async';

import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/main.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/html/html_util.dart';
import 'package:bloc/bloc.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/cupertino.dart';
import 'package:meta/meta.dart';
import 'package:moor/moor.dart';

import '../blocs.dart';

part 'sync_state.dart';

const kRequiredTxConfirmationCount = 15;

/// The [SyncCubit] periodically syncs the user's owned and attached drives and their contents.
/// It also checks the status of unconfirmed transactions made by revisions.
class SyncCubit extends Cubit<SyncState> {
  final ProfileCubit _profileCubit;
  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final Database _db;

  StreamSubscription? _syncSub;

  SyncCubit({
    required ProfileCubit profileCubit,
    required ArweaveService arweave,
    required DriveDao driveDao,
    required Database db,
  })  : _profileCubit = profileCubit,
        _arweave = arweave,
        _driveDao = driveDao,
        _db = db,
        super(SyncIdle()) {
    // Sync the user's drives on start and periodically.
    createSyncStream();
    restartSyncOnFocus();
  }

  void createSyncStream() {
    _syncSub?.cancel();
    _syncSub = Stream.periodic(const Duration(minutes: 2))
        // Do not start another sync until the previous sync has completed.
        .map((value) => Stream.fromFuture(startSync()))
        .listen((_) {});
    startSync();
  }

  void restartSyncOnFocus() {
    whenBrowserTabIsUnhidden(() => Future.delayed(Duration(seconds: 2))
        .then((value) => createSyncStream()));
  }

  final List<String> missingParentIds = [];

  Future<void> startSync() async {
    try {
      final profile = _profileCubit.state;
      print('Syncing...');
      emit(SyncInProgress());
      // Only sync in drives owned by the user if they're logged in.
      if (profile is ProfileLoggedIn) {
        //Check if profile is ArConnect to skip sync while tab is hidden
        final isArConnect = await _profileCubit.isCurrentProfileArConnect();

        if (isArConnect && isBrowserTabHidden()) {
          print('Tab hidden, skipping sync...');
          emit(SyncIdle());
          return;
        }

        if (await _profileCubit.logoutIfWalletMismatch()) {
          emit(SyncWalletMismatch());
          return;
        }
        // This syncs in the latest info on drives owned by the user and will be overwritten
        // below when the full sync process is ran.
        //
        // It also adds the encryption keys onto the drive models which isn't touched by the
        // later system.
        //
        final userDriveEntities = await _arweave.getUniqueUserDriveEntities(
            profile.wallet, profile.password);

        await _driveDao.updateUserDrives(userDriveEntities, profile.cipherKey);
      }

      // Sync the contents of each drive attached in the app.
      final drives = await _driveDao.allDrives().map((d) => d).get();
      final currentBlockHeight = await arweave.getCurrentBlockHeight();

      final driveSyncProcesses = drives.map((drive) => _syncDrive(
            drive.id,
            lastBlockHeight: drive.lastBlockHeight!,
            currentBlockheight: currentBlockHeight,
          ).onError((error, stackTrace) {
            print('Error syncing drive with id ${drive.id}');
            print(error.toString() + stackTrace.toString());
            addError(error!);
          }));
      await Future.wait(driveSyncProcesses);

      await Future.wait([
        if (profile is ProfileLoggedIn) _profileCubit.refreshBalance(),
        _updateTransactionStatuses(),
      ]);
    } catch (err) {
      addError(err);
    }

    emit(SyncIdle());
  }

  Future<void> _syncDrive(
    String driveId, {
    required int currentBlockheight,
    required int lastBlockHeight,
    String? syncCursor,
  }) async {
    final drive = await _driveDao.driveById(driveId: driveId).getSingle();
    final owner = await arweave.getOwnerForDriveEntityWithId(driveId);
    SecretKey? driveKey;
    if (drive.isPrivate) {
      final profile = _profileCubit.state;

      // Only sync private drives when the user is logged in.
      if (profile is ProfileLoggedIn) {
        driveKey = await _driveDao.getDriveKey(drive.id, profile.cipherKey);
      } else {
        return;
      }
    }
    final entityHistory = await _arweave.getNewEntitiesForDrive(
      drive.id,
      lastBlockHeight: lastBlockHeight,
      after: syncCursor,
      driveKey: driveKey,
      owner: owner,
    );

    // Create entries for all the new revisions of file and folders in this drive.
    final newEntities = entityHistory.blockHistory
        .map((b) => b.entities)
        .expand((entities) => entities);
    // Handle newEntities being empty, i.e; There's nothing more to sync
    if ((newEntities.isEmpty && entityHistory.cursor == null)) {
      // Reset the sync cursor after every sync to pick up files from other instances of the app.
      // (Different tab, different window, mobile, desktop etc)
      await _driveDao.writeToDrive(DrivesCompanion(
        id: Value(drive.id),
        lastBlockHeight: Value(currentBlockheight),
        syncCursor: Value(null),
      ));

      //Finalize missing parent list
      for (var id in missingParentIds) {
        if ((await _driveDao
                .folderById(driveId: drive.id, folderId: id)
                .getSingleOrNull()) !=
            null) {
          missingParentIds.remove(id);
        }
      }
      if(missingParentIds.isNotEmpty){
        emit(SyncOrphansDetected());
      }
      emit(SyncEmpty());
      return;
    }

    await _db.transaction(() async {
      final latestDriveRevision = await _addNewDriveEntityRevisions(
          newEntities.whereType<DriveEntity>());
      final latestFolderRevisions = await _addNewFolderEntityRevisions(
          driveId, newEntities.whereType<FolderEntity>());
      final latestFileRevisions = await _addNewFileEntityRevisions(
          driveId, newEntities.whereType<FileEntity>());

      // Check and handle cases where there's no more revisions
      final updatedDrive = latestDriveRevision != null
          ? await _computeRefreshedDriveFromRevision(latestDriveRevision)
          : null;

      final updatedFoldersById =
          await _computeRefreshedFolderEntriesFromRevisions(
              driveId, latestFolderRevisions);
      final updatedFilesById = await _computeRefreshedFileEntriesFromRevisions(
          driveId, latestFileRevisions);

      // Update the drive model, making sure to not overwrite the existing keys defined on the drive.
      if (updatedDrive != null) {
        await (_db.update(_db.drives)..whereSamePrimaryKey(updatedDrive))
            .write(updatedDrive);
      }

      // Update the folder and file entries before generating their new paths.
      await _db.batch((b) {
        b.insertAllOnConflictUpdate(
            _db.folderEntries, updatedFoldersById.values.toList());
        b.insertAllOnConflictUpdate(
            _db.fileEntries, updatedFilesById.values.toList());
      });

      await generateFsEntryPaths(driveId, updatedFoldersById, updatedFilesById);
    });

    // If there are more results to process, recurse.
    await _syncDrive(
      driveId,
      syncCursor: entityHistory.cursor,
      lastBlockHeight: lastBlockHeight,
      currentBlockheight: currentBlockheight,
    );
  }

  /// Computes the new drive revisions from the provided entities, inserts them into the database,
  /// and returns the latest revision.
  Future<DriveRevisionsCompanion?> _addNewDriveEntityRevisions(
    Iterable<DriveEntity> newEntities,
  ) async {
    DriveRevisionsCompanion? latestRevision;

    final newRevisions = <DriveRevisionsCompanion>[];
    for (final entity in newEntities) {
      latestRevision ??= await _driveDao
          .latestDriveRevisionByDriveId(driveId: entity.id!)
          .getSingleOrNull()
          .then((r) => r?.toCompanion(true));

      final revisionPerformedAction =
          entity.getPerformedRevisionAction(latestRevision);
      if (revisionPerformedAction == null) {
        continue;
      }
      final revision =
          entity.toRevisionCompanion(performedAction: revisionPerformedAction);

      if (revision.action.value.isEmpty) {
        continue;
      }

      newRevisions.add(revision);
      latestRevision = revision;
    }

    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.driveRevisions, newRevisions);
      b.insertAllOnConflictUpdate(
          _db.networkTransactions,
          newRevisions
              .map(
                (rev) => NetworkTransactionsCompanion.insert(
                  id: rev.metadataTxId.value,
                  status: Value(TransactionStatus.confirmed),
                ),
              )
              .toList());
    });

    return latestRevision;
  }

  /// Computes the new folder revisions from the provided entities, inserts them into the database,
  /// and returns only the latest revisions.
  Future<List<FolderRevisionsCompanion>> _addNewFolderEntityRevisions(
      String driveId, Iterable<FolderEntity> newEntities) async {
    // The latest folder revisions, keyed by their entity ids.
    final latestRevisions = <String, FolderRevisionsCompanion>{};

    final newRevisions = <FolderRevisionsCompanion>[];
    for (final entity in newEntities) {
      if (!latestRevisions.containsKey(entity.id)) {
        final revisions = (await _driveDao
            .latestFolderRevisionByFolderId(
                driveId: driveId, folderId: entity.id!)
            .getSingleOrNull());
        if (revisions != null) {
          latestRevisions[entity.id!] = revisions.toCompanion(true);
        }
      }

      final revisionPerformedAction =
          entity.getPerformedRevisionAction(latestRevisions[entity.id]);
      if (revisionPerformedAction == null) {
        continue;
      }
      final revision =
          entity.toRevisionCompanion(performedAction: revisionPerformedAction);

      if (revision.action.value.isEmpty) {
        continue;
      }

      newRevisions.add(revision);
      latestRevisions[entity.id!] = revision;
    }

    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.folderRevisions, newRevisions);
      b.insertAllOnConflictUpdate(
          _db.networkTransactions,
          newRevisions
              .map(
                (rev) => NetworkTransactionsCompanion.insert(
                  id: rev.metadataTxId.value,
                  status: Value(TransactionStatus.confirmed),
                ),
              )
              .toList());
    });

    return latestRevisions.values.toList();
  }

  /// Computes the new file revisions from the provided entities, inserts them into the database,
  /// and returns only the latest revisions.
  Future<List<FileRevisionsCompanion>> _addNewFileEntityRevisions(
      String driveId, Iterable<FileEntity> newEntities) async {
    // The latest file revisions, keyed by their entity ids.
    final latestRevisions = <String, FileRevisionsCompanion>{};

    final newRevisions = <FileRevisionsCompanion>[];
    for (final entity in newEntities) {
      if (!latestRevisions.containsKey(entity.id) &&
          entity.parentFolderId != null) {
        final revisions = await _driveDao
            .latestFileRevisionByFileId(driveId: driveId, fileId: entity.id!)
            .getSingleOrNull();
        if (revisions != null) {
          latestRevisions[entity.id!] = revisions.toCompanion(true);
        }
      }

      final revisionPerformedAction =
          entity.getPerformedRevisionAction(latestRevisions[entity.id]);
      if (revisionPerformedAction == null) {
        continue;
      }
      // If Parent-Folder-Id is missing for a file, put it in the rootfolder

      entity.parentFolderId = entity.parentFolderId ?? rootPath;
      final revision =
          entity.toRevisionCompanion(performedAction: revisionPerformedAction);

      if (revision.action.value.isEmpty) {
        continue;
      }

      newRevisions.add(revision);
      latestRevisions[entity.id!] = revision;
    }

    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.fileRevisions, newRevisions);
      b.insertAllOnConflictUpdate(
          _db.networkTransactions,
          newRevisions
              .expand(
                (rev) => [
                  NetworkTransactionsCompanion.insert(
                    id: rev.metadataTxId.value,
                    status: Value(TransactionStatus.confirmed),
                  ),
                  // We cannot be sure that the data tx of files have been mined
                  // so we'll mark it as pending initially.
                  NetworkTransactionsCompanion.insert(
                    id: rev.dataTxId.value,
                    status: Value(TransactionStatus.pending),
                  ),
                ],
              )
              .toList());
    });

    return latestRevisions.values.toList();
  }

  /// Computes the refreshed drive entries from the provided revisions and returns them as a map keyed by their ids.
  Future<DrivesCompanion> _computeRefreshedDriveFromRevision(
      DriveRevisionsCompanion latestRevision) async {
    final oldestRevision = await _driveDao
        .oldestDriveRevisionByDriveId(driveId: latestRevision.driveId.value)
        .getSingleOrNull();

    return latestRevision.toEntryCompanion().copyWith(
        dateCreated: Value(oldestRevision?.dateCreated ??
            latestRevision.dateCreated as DateTime));
  }

  /// Computes the refreshed folder entries from the provided revisions and returns them as a map keyed by their ids.
  Future<Map<String, FolderEntriesCompanion>>
      _computeRefreshedFolderEntriesFromRevisions(String driveId,
          List<FolderRevisionsCompanion> revisionsByFolderId) async {
    final updatedFoldersById = {
      for (final revision in revisionsByFolderId)
        revision.folderId.value: revision.toEntryCompanion(),
    };

    for (final folderId in updatedFoldersById.keys) {
      final oldestRevision = await _driveDao
          .oldestFolderRevisionByFolderId(driveId: driveId, folderId: folderId)
          .getSingleOrNull();

      updatedFoldersById[folderId] = updatedFoldersById[folderId]!.copyWith(
          dateCreated: Value(oldestRevision?.dateCreated ??
              updatedFoldersById[folderId]!.dateCreated as DateTime));
    }

    return updatedFoldersById;
  }

  /// Computes the refreshed file entries from the provided revisions and returns them as a map keyed by their ids.
  Future<Map<String, FileEntriesCompanion>>
      _computeRefreshedFileEntriesFromRevisions(String driveId,
          List<FileRevisionsCompanion> revisionsByFileId) async {
    final updatedFilesById = {
      for (final revision in revisionsByFileId)
        revision.fileId.value: revision.toEntryCompanion(),
    };

    for (final fileId in updatedFilesById.keys) {
      final oldestRevision = await _driveDao
          .oldestFileRevisionByFileId(driveId: driveId, fileId: fileId)
          .getSingleOrNull();

      updatedFilesById[fileId] = updatedFilesById[fileId]!.copyWith(
          dateCreated: Value(oldestRevision?.dateCreated ??
              updatedFilesById[fileId]!.dateCreated as DateTime));
    }

    return updatedFilesById;
  }

  /// Generates paths for the folders (and their subchildren) and files provided.
  Future<void> generateFsEntryPaths(
    String driveId,
    Map<String, FolderEntriesCompanion> foldersByIdMap,
    Map<String, FileEntriesCompanion> filesByIdMap,
  ) async {
    final staleFolderTree = <FolderNode>[];
    for (final folder in foldersByIdMap.values) {
      // Get trees of the updated folders and files for path generation.
      final tree = await _driveDao.getFolderTree(driveId, folder.id.value);

      // Remove any trees that are a subset of another.
      var newTreeIsSubsetOfExisting = false;
      var newTreeIsSupersetOfExisting = false;
      for (final existingTree in staleFolderTree) {
        if (existingTree.searchForFolder(tree.folder.id) != null) {
          newTreeIsSubsetOfExisting = true;
        } else if (tree.searchForFolder(existingTree.folder.id) != null) {
          staleFolderTree.remove(existingTree);
          staleFolderTree.add(tree);
          newTreeIsSupersetOfExisting = true;
        }
      }

      if (!newTreeIsSubsetOfExisting && !newTreeIsSupersetOfExisting) {
        staleFolderTree.add(tree);
      }
    }

    Future<void> updateFolderTree(FolderNode node, String parentPath) async {
      final folderId = node.folder.id;
      // If this is the root folder, we should not include its name as part of the path.
      final folderPath = node.folder.parentFolderId != null
          ? parentPath + '/' + node.folder.name
          : rootPath;

      await _driveDao
          .updateFolderById(driveId, folderId)
          .write(FolderEntriesCompanion(path: Value(folderPath)));

      for (final staleFileId in node.files.keys) {
        final filePath = folderPath + '/' + node.files[staleFileId]!;

        await _driveDao
            .updateFileById(driveId, staleFileId)
            .write(FileEntriesCompanion(path: Value(filePath)));
      }

      for (final staleFolder in node.subfolders) {
        await updateFolderTree(staleFolder, folderPath);
      }
    }

    for (final treeRoot in staleFolderTree) {
      // Get the path of this folder's parent.
      String? parentPath;
      if (treeRoot.folder.parentFolderId == null) {
        parentPath = rootPath;
      } else {
        parentPath = (await _driveDao
            .folderById(
                driveId: driveId, folderId: treeRoot.folder.parentFolderId!)
            .map((f) => f.path)
            .getSingleOrNull());
      }
      if (parentPath != null) {
        await updateFolderTree(treeRoot, parentPath);
      } else {
        if (!missingParentIds.contains(treeRoot.folder.parentFolderId)) {
          missingParentIds.add(treeRoot.folder.parentFolderId!);
        }
        print('Missing parent folder');
      }
    }

    // Update paths of files whose parent folders were not updated.
    final staleOrphanFiles = filesByIdMap.values
        .where((f) => !foldersByIdMap.containsKey(f.parentFolderId));
    for (final staleOrphanFile in staleOrphanFiles) {
      if (staleOrphanFile.parentFolderId.value.isNotEmpty) {
        final parentPath = await _driveDao
            .folderById(
                driveId: driveId,
                folderId: staleOrphanFile.parentFolderId.value)
            .map((f) => f.path)
            .getSingleOrNull();

        if (parentPath != null) {
          final filePath = parentPath + '/' + staleOrphanFile.name.value;

          await _driveDao.writeToFile(FileEntriesCompanion(
              id: staleOrphanFile.id,
              driveId: staleOrphanFile.driveId,
              path: Value(filePath)));
        } else {
          print(
              'Stale orphan file ${staleOrphanFile.id.value} parent folder ${staleOrphanFile.parentFolderId.value} could not be found.');
        }
      }
    }
  }

  Future<void> _updateTransactionStatuses() async {
    final pendingTxMap = {
      for (final tx in await _driveDao.pendingTransactions().get()) tx.id: tx,
    };

    final txConfirmations =
        await _arweave.getTransactionConfirmations(pendingTxMap.keys.toList());

    await _driveDao.transaction(() async {
      for (final txId in pendingTxMap.keys) {
        final txConfirmed =
            txConfirmations[txId]! >= kRequiredTxConfirmationCount;
        final txNotFound = txConfirmations[txId]! < 0;

        var txStatus;

        if (txConfirmed) {
          txStatus = TransactionStatus.confirmed;
        } else if (txNotFound) {
          // Only mark transactions as failed if they are unconfirmed for over 45 minutes
          // as the transaction might not be queryable for right after it was created.
          final abovePendingThreshold = DateTime.now()
                  .difference(pendingTxMap[txId]!.dateCreated)
                  .inMinutes >
              45;
          if (abovePendingThreshold) {
            txStatus = TransactionStatus.failed;
          }
        }

        if (txStatus != null) {
          await _driveDao.writeToTransaction(
            NetworkTransactionsCompanion(
              id: Value(txId),
              status: Value(txStatus),
            ),
          );
        }
      }
    });
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(SyncFailure(error: error, stackTrace: stackTrace));
    super.onError(error, stackTrace);
    emit(SyncIdle());

    print('Failed to sync: $error $stackTrace');
  }

  @override
  Future<void> close() {
    _syncSub?.cancel();
    return super.close();
  }
}
