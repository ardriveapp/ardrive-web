import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/cost_estimate.dart';
import 'package:ardrive/blocs/upload/models/models.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/extensions.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';

import 'enums/conflicting_files_actions.dart';

part 'upload_state.dart';

const privateFileSizeLimit = 104857600;
const publicFileSizeLimit = 1288490189;

final filesNamesToExclude = ['.DS_Store'];

class UploadCubit extends Cubit<UploadState> {
  final String driveId;
  final String folderId;

  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final ArweaveService _arweave;
  final PstService _pst;
  final UploadPlanUtils _uploadPlanUtils;

  late bool uploadFolders;
  late Drive _targetDrive;
  late FolderEntry _targetFolder;

  List<UploadFile> files = [];
  Map<String, WebFolder> foldersByPath = {};

  /// Map of conflicting file ids keyed by their file names.
  final Map<String, String> conflictingFiles = {};
  final List<String> conflictingFolders = [];

  bool fileSizeWithinBundleLimits(int size) => size < bundleSizeLimit;

  UploadCubit({
    required this.driveId,
    required this.folderId,
    required this.files,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
    required ArweaveService arweave,
    required PstService pst,
    required UploadPlanUtils uploadPlanUtils,
    this.uploadFolders = false,
  })  : _profileCubit = profileCubit,
        _driveDao = driveDao,
        _arweave = arweave,
        _pst = pst,
        _uploadPlanUtils = uploadPlanUtils,
        super(UploadPreparationInProgress());

  Future<void> startUploadPreparation() async {
    files.removeWhere((file) => filesNamesToExclude.contains(file.ioFile.name));
    _targetDrive = await _driveDao.driveById(driveId: driveId).getSingle();
    _targetFolder = await _driveDao
        .folderById(driveId: driveId, folderId: folderId)
        .getSingle();
    emit(UploadPreparationInitialized());
  }

  Future<void> checkConflicts() async {
    if (uploadFolders) {
      return await checkConflictingFolders();
    }

    await checkConflictingFiles();
  }

  /// Tries to find a files that conflict with the files in the target folder.
  ///
  /// If there's one, prompt the user to upload the file as a version of the existing one.
  /// If there isn't one, prepare to upload the file.
  Future<void> checkConflictingFolders() async {
    emit(UploadPreparationInProgress());
    if (uploadFolders) {
      final folderPrepareResult =
          await generateFoldersAndAssignParentsForFiles(files);
      files = folderPrepareResult.files;
      foldersByPath = folderPrepareResult.foldersByPath;
    }
    for (final file in files) {
      final fileName = file.ioFile.name;

      final existingFolderName = await _driveDao
          .foldersInFolderWithName(
            driveId: _targetDrive.id,
            parentFolderId: file.parentFolderId,
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

  void checkFilesAboveLimit() async {
    final tooLargeFiles = [
      for (final file in files)
        if (await file.ioFile.length > sizeLimit) file.ioFile.name
    ];

    if (tooLargeFiles.isNotEmpty) {
      emit(
        UploadFileTooLarge(
          hasFilesToUpload: files.length > tooLargeFiles.length,
          tooLargeFileNames: tooLargeFiles,
          isPrivate: _targetDrive.isPrivate,
        ),
      );
      return;
    }

    // If we don't have any file above limit, we can check conflicts
    checkConflicts();
  }

  Future<void> checkConflictingFiles() async {
    emit(UploadPreparationInProgress());

    _removeFilesWithFolderNameConflicts();

    for (final file in files) {
      final fileName = file.ioFile.name;
      final existingFileId = await _driveDao
          .filesInFolderWithName(
            driveId: _targetDrive.id,
            parentFolderId: file.parentFolderId,
            name: fileName,
          )
          .map((f) => f.id)
          .getSingleOrNull();

      if (existingFileId != null) {
        conflictingFiles[file.getIdentifier()] = existingFileId;
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
  Future<FolderPrepareResult> generateFoldersAndAssignParentsForFiles(
    List<UploadFile> files,
  ) async {
    final folders = UploadPlanUtils.generateFoldersForFiles(files);
    final foldersToSkip = [];
    for (var folder in folders.values) {
      //If The folders map contains the immediate ancestor of the current folder
      //we use the id of that folder, otherwise use targetFolder as root

      folder.parentFolderId = folders.containsKey(folder.parentFolderPath)
          ? folders[folder.parentFolderPath]!.id
          : _targetFolder.id;
      final existingFolderId = await _driveDao
          .foldersInFolderWithName(
            driveId: driveId,
            name: folder.name,
            parentFolderId: folder.parentFolderId,
          )
          .map((f) => f.id)
          .getSingleOrNull();
      final existingFileId = await _driveDao
          .filesInFolderWithName(
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
        foldersToSkip.add(folder);
      }
      if (existingFileId != null) {
        conflictingFolders.add(folder.name);
      }
      folder.path = folder.parentFolderPath.isNotEmpty
          ? '${_targetFolder.path}/${folder.parentFolderPath}/${folder.name}'
          : '${_targetFolder.path}/${folder.name}';
    }
    final filesToUpload = <UploadFile>[];
    for (var file in files) {
      final fileFolder = getDirname(file.ioFile.path);
      filesToUpload.add(
        UploadFile(
          ioFile: file.ioFile,
          parentFolderId: folders[fileFolder]?.id ?? _targetFolder.id,
        ),
      );
    }
    folders.removeWhere((key, value) => foldersToSkip.contains(value));
    return FolderPrepareResult(files: filesToUpload, foldersByPath: folders);
  }

  Future<void> prepareUploadPlanAndCostEstimates({
    UploadActions? uploadAction,
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

    if (uploadAction == UploadActions.skip) {
      _removeFilesWithFileNameConflicts();
    }

    final uploadPlan = await _uploadPlanUtils.filesToUploadPlan(
      targetFolder: _targetFolder,
      targetDrive: _targetDrive,
      files: files,
      cipherKey: profile.cipherKey,
      wallet: profile.wallet,
      conflictingFiles: conflictingFiles,
      foldersByPath: foldersByPath,
    );
    try {
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
    } catch (error) {
      addError(error);
    }
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

    // Upload Bundles
    for (var bundleHandle in uploadPlan.bundleUploadHandles) {
      try {
        await bundleHandle.prepareAndSignBundleTransaction(
          arweaveService: _arweave,
          driveDao: _driveDao,
          pstService: _pst,
          wallet: profile.wallet,
        );
      } catch (error) {
        addError(error);
      }

      await for (final _ in bundleHandle
          .upload(_arweave)
          .debounceTime(const Duration(milliseconds: 500))
          .handleError((_) => addError('Fatal upload error.'))) {
        emit(UploadInProgress(uploadPlan: uploadPlan));
      }
      bundleHandle.dispose();
    }

    // Upload V2 Files
    for (final uploadHandle in uploadPlan.fileV2UploadHandles.values) {
      try {
        await uploadHandle.prepareAndSignTransactions(
            arweaveService: _arweave, wallet: profile.wallet, pstService: _pst);
        await uploadHandle.writeFileEntityToDatabase(
          driveDao: _driveDao,
        );
      } catch (error) {
        addError(error);
      }

      await for (final _ in uploadHandle
          .upload(_arweave)
          .debounceTime(const Duration(milliseconds: 500))
          .handleError((_) => addError('Fatal upload error.'))) {
        emit(UploadInProgress(uploadPlan: uploadPlan));
      }
      uploadHandle.dispose();
    }
    unawaited(_profileCubit.refreshBalance());

    emit(UploadComplete());
  }

  Future<void> skipLargeFilesAndCheckForConflicts() async {
    for (final file in files) {
      if (await file.ioFile.length > sizeLimit) {
        files.remove(file);
      }
    }
    await checkConflicts();
  }

  void _removeFilesWithFileNameConflicts() {
    files.removeWhere((file) => conflictingFiles.containsKey(
        file.ioFile.path.isEmpty ? file.ioFile.name : file.ioFile.path));
  }

  num get sizeLimit =>
      _targetDrive.isPrivate ? privateFileSizeLimit : publicFileSizeLimit;

  void _removeFilesWithFolderNameConflicts() {
    files.removeWhere((file) => conflictingFolders.contains(file.ioFile.name));
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(UploadFailure());
    'Failed to upload file: $error $stackTrace'.logError();
    super.onError(error, stackTrace);
  }
}
