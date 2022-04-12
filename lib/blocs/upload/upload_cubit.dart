import 'dart:async';
import 'dart:math' as math;

import 'package:ardrive/blocs/upload/cost_estimate.dart';
import 'package:ardrive/blocs/upload/upload_file.dart';
import 'package:ardrive/blocs/upload/upload_plan.dart';
import 'package:ardrive/blocs/upload/web_file.dart';
import 'package:ardrive/blocs/upload/web_folder.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/folder_entity.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:pedantic/pedantic.dart';
import 'package:rxdart/rxdart.dart';

import '../blocs.dart';
import 'enums/conflicting_files_actions.dart';

part 'upload_state.dart';

final privateFileSizeLimit = 104857600;
final publicFileSizeLimit = 1.25 * math.pow(10, 9);
final minimumPstTip = BigInt.from(10000000);

class UploadCubit extends Cubit<UploadState> {
  final String driveId;
  final String folderId;
  final List<UploadFile> files;

  final ProfileCubit _profileCubit;
  final SyncCubit _syncCubit;
  final DriveDao _driveDao;
  final ArweaveService _arweave;
  final PstService _pst;
  final UploadPlanUtils _uploadPlanUtils;
  late bool uploadFolders;
  late Drive _targetDrive;
  late FolderEntry _targetFolder;

  /// Map of conflicting file ids keyed by their file names.
  final Map<String, String> conflictingFiles = {};
  final Map<String, WebFolder> foldersToUpload = {};
  final List<String> conflictingFolders = [];

  bool fileSizeWithinBundleLimits(int size) => size < bundleSizeLimit;

  UploadCubit({
    required this.driveId,
    required this.folderId,
    required this.files,
    required ProfileCubit profileCubit,
    required SyncCubit syncCubit,
    required DriveDao driveDao,
    required ArweaveService arweave,
    required PstService pst,
    required UploadPlanUtils uploadPlanUtils,
    this.uploadFolders = false,
  })  : _profileCubit = profileCubit,
        _driveDao = driveDao,
        _arweave = arweave,
        _syncCubit = syncCubit,
        _pst = pst,
        _uploadPlanUtils = uploadPlanUtils,
        super(UploadPreparationInProgress());

  Future<void> startUploadPreparation() async {
    _targetDrive = await _driveDao.driveById(driveId: driveId).getSingle();
    _targetFolder = await _driveDao
        .folderById(driveId: driveId, folderId: folderId)
        .getSingle();
    emit(UploadPreparationInitialized());
  }

  /// Tries to find a files that conflict with the files in the target folder.
  ///
  /// If there's one, prompt the user to upload the file as a version of the existing one.
  /// If there isn't one, prepare to upload the file.

  Future<void> checkConflictingFolders() async {
    emit(UploadPreparationInProgress());

    for (final file in files) {
      final fileName = file.name;

      final existingFolderName = await _driveDao
          .foldersInFolderWithName(
            driveId: _targetDrive.id,
            parentFolderId: _targetFolder.id,
            name: fileName,
          )
          .map((f) => f.name)
          .getSingleOrNull();

      if (existingFolderName != null) {
        conflictingFolders.add(existingFolderName);
      }
    }

    if (conflictingFolders.isNotEmpty) {
      emit(
        UploadFolderNameConflict(
          areAllFilesConflicting: conflictingFolders.length == files.length,
          conflictingFileNames: conflictingFolders,
        ),
      );
    } else {
      await checkConflictingFiles();
    }
  }

  Future<void> checkConflictingFiles() async {
    emit(UploadPreparationInProgress());

    _removeFilesWithFolderNameConflicts();

    for (final file in files) {
      final fileName = file.name;
      final existingFileId = await _driveDao
          .filesInFolderWithName(
            driveId: _targetDrive.id,
            parentFolderId: _targetFolder.id,
            name: fileName,
          )
          .map((f) => f.id)
          .getSingleOrNull();

      if (existingFileId != null) {
        conflictingFiles[fileName] = existingFileId;
      }
    }

    if (conflictingFiles.isNotEmpty) {
      emit(
        UploadFileConflict(
          areAllFilesConflicting: conflictingFiles.length == files.length,
          conflictingFileNames: conflictingFiles.keys.toList(),
        ),
      );
    } else {
      await prepareUploadPlanAndCostEstimates();
    }
  }

  /// Generate Folders and assign parentFolderIds

  List<UploadFile> generateFoldersForFiles(List<UploadFile> files) {
    final folders = UploadPlanUtils.generateFoldersForFiles(
      files as List<WebFile>,
    );
    folders.forEach((key, folder) async {
      final existingFolderId = await _driveDao
          .foldersInFolderWithName(
            driveId: driveId,
            name: folder.name,
            parentFolderId: folders[folder.parentFolderPath] != null
                ? folders[folder.parentFolderPath]!.id
                : _targetFolder.id,
          )
          .map((f) => f.id)
          .getSingleOrNull();
      if (existingFolderId != null) {
        folder.id = existingFolderId;
      }
    });
    final filesToUpload = <UploadFile>[];
    files.forEach((file) {
      final fileFolder = (file.path.split('/')..removeLast()).join('/');
      print(folders.keys);
      print(folders[fileFolder]?.id);

      filesToUpload.add(WebFile(
        file.file,
        folders[fileFolder]?.id ?? _targetFolder.id,
      ));
    });
    print(filesToUpload.map((e) => e.parentFolderId));
    foldersToUpload.addAll(folders);
    return filesToUpload;
  }

  /// If `conflictingFileAction` is null, means that had no conflict.
  Future<void> prepareUploadPlanAndCostEstimates({
    ConflictingFileActions? conflictingFileAction,
  }) async {
    final profile = _profileCubit.state as ProfileLoggedIn;

    if (await _profileCubit.checkIfWalletMismatch()) {
      emit(UploadWalletMismatch());
      return;
    }

    emit(
      UploadPreparationInProgress(
        isArConnect: await _profileCubit.isCurrentProfileArConnect(),
      ),
    );
    final sizeLimit =
        _targetDrive.isPrivate ? privateFileSizeLimit : publicFileSizeLimit;

    if (conflictingFileAction == ConflictingFileActions.Skip) {
      _removeFilesWithFileNameConflicts();
    }

    final tooLargeFiles = [
      for (final file in files)
        if (file.size > sizeLimit) file.name
    ];

    if (tooLargeFiles.isNotEmpty) {
      emit(UploadFileTooLarge(
        tooLargeFileNames: tooLargeFiles,
        isPrivate: _targetDrive.isPrivate,
      ));
      return;
    }

    final uploadPlan = await _uploadPlanUtils.filesToUploadPlan(
      folderEntry: _targetFolder,
      targetDrive: _targetDrive,
      files: uploadFolders ? generateFoldersForFiles(files) : files,
      cipherKey: profile.cipherKey,
      wallet: profile.wallet,
      conflictingFiles: conflictingFiles,
    );

    final costEstimate = await CostEstimate.create(
      uploadPlan: uploadPlan,
      arweaveService: _arweave,
      pstService: _pst,
      wallet: profile.wallet,
    );

    if (await _profileCubit.checkIfWalletMismatch()) {
      emit(UploadWalletMismatch());
      return;
    }

    emit(
      UploadReady(
        costEstimate: costEstimate,
        uploadIsPublic: _targetDrive.isPublic,
        sufficientArBalance: profile.walletBalance >= costEstimate.totalCost,
        uploadPlan: uploadPlan,
      ),
    );
  }

  Future<void> startUpload({
    required UploadPlan uploadPlan,
    required CostEstimate costEstimate,
  }) async {
    final profile = _profileCubit.state as ProfileLoggedIn;

    //Check if the same wallet it being used before starting upload.
    if (await _profileCubit.checkIfWalletMismatch()) {
      emit(UploadWalletMismatch());
      return;
    }
    emit(
      UploadSigningInProgress(
        uploadPlan: uploadPlan,
        isArConnect: await _profileCubit.isCurrentProfileArConnect(),
      ),
    );

    if (costEstimate.v2FilesFeeTx != null) {
      await _arweave.postTx(costEstimate.v2FilesFeeTx!);
    }

    //Upload folders
    final folderMap = <String, FolderEntity>{};
    final filesMap = <String, FileEntity>{};
    foldersToUpload.forEach((key, folder) async {
      await _driveDao.transaction(() async {
        final driveKey = _targetDrive.isPrivate
            ? await _driveDao.getDriveKey(_targetDrive.id, profile.cipherKey)
            : null;

        final parentFolderId =
            foldersToUpload[folder.parentFolderPath]?.id ?? _targetFolder.id;

        await _driveDao.createFolder(
          driveId: _targetDrive.id,
          parentFolderId: parentFolderId,
          folderName: folder.name,
          path:
              '${_targetFolder.path}/${folder.parentFolderPath}/${folder.name}',
        );

        final folderEntity = FolderEntity(
          id: folder.id,
          driveId: _targetFolder.driveId,
          parentFolderId: parentFolderId,
          name: folder.name,
        );

        final folderTx = await _arweave.prepareEntityTx(
          folderEntity,
          profile.wallet,
          driveKey,
        );

        await _arweave.postTx(folderTx);
        folderEntity.txId = folderTx.id;
        await _driveDao.insertFolderRevision(
          folderEntity.toRevisionCompanion(
            performedAction: RevisionAction.create,
          ),
        );

        folderMap.putIfAbsent(folder.id, () => folderEntity);
      });

      filesMap.addEntries(uploadPlan.bundleUploadHandles
          .map((e) => e.fileEntities)
          .expand((list) => list)
          .map((file) => MapEntry(file.id!, file)));
      filesMap.addAll(
        uploadPlan.v2FileUploadHandles
            .map((key, value) => MapEntry(key, value.entity)),
      );
    });

    // Upload Bundles
    for (var bundleHandle in uploadPlan.bundleUploadHandles) {
      await bundleHandle.prepareAndSignBundleTransaction(
        arweaveService: _arweave,
        driveDao: _driveDao,
        pstService: _pst,
        wallet: profile.wallet,
      );
      await for (final _ in bundleHandle
          .upload(_arweave)
          .debounceTime(Duration(milliseconds: 500))
          .handleError((_) => addError('Fatal upload error.'))) {
        emit(UploadInProgress(uploadPlan: uploadPlan));
      }
      bundleHandle.dispose();
    }

    // Upload V2 Files
    for (final uploadHandle in uploadPlan.v2FileUploadHandles.values) {
      await uploadHandle.prepareAndSignTransactions(
        arweaveService: _arweave,
        wallet: profile.wallet,
      );
      await uploadHandle.writeFileEntityToDatabase(
        driveDao: _driveDao,
      );
      await for (final _ in uploadHandle
          .upload(_arweave)
          .debounceTime(Duration(milliseconds: 500))
          .handleError((_) => addError('Fatal upload error.'))) {
        emit(UploadInProgress(uploadPlan: uploadPlan));
      }
      uploadHandle.dispose();
    }
    unawaited(_driveDao.generateFsEntryPaths(driveId, folderMap, filesMap));
    unawaited(_profileCubit.refreshBalance());

    emit(UploadComplete());
  }

  void _removeFilesWithFileNameConflicts() {
    files.removeWhere((element) => conflictingFiles.containsKey(element.name));
  }

  void _removeFilesWithFolderNameConflicts() {
    files.removeWhere((element) => conflictingFolders.contains(element.name));
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(UploadFailure());
    super.onError(error, stackTrace);

    print('Failed to upload file: $error $stackTrace');
  }
}
