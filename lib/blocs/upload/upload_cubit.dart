import 'dart:async';
import 'dart:math' as math;

import 'package:ardrive/blocs/upload/cost_estimate.dart';
import 'package:ardrive/blocs/upload/upload_file.dart';
import 'package:ardrive/blocs/upload/upload_plan.dart';
import 'package:ardrive/blocs/upload/web_file.dart';
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
  final DriveDao _driveDao;
  final ArweaveService _arweave;
  final PstService _pst;
  final UploadPlanUtils _uploadPlanUtils;
  late bool uploadFolders;
  late Drive _targetDrive;
  late FolderEntry _targetFolder;

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
    if (uploadFolders) {
      final folders = UploadPlanUtils.generateFoldersForFiles(
        files as List<WebFile>,
        _targetFolder.id,
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
    }
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
        files: files,
        cipherKey: profile.cipherKey,
        wallet: profile.wallet,
        conflictingFiles: conflictingFiles);
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
