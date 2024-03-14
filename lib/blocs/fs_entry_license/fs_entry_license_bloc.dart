import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/forms/cc.dart';
import 'package:ardrive/models/forms/udl.dart';
import 'package:ardrive/models/license.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// ignore: depend_on_referenced_packages
import 'package:platform/platform.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'fs_entry_license_event.dart';
part 'fs_entry_license_state.dart';

class FsEntryLicenseBloc
    extends Bloc<FsEntryLicenseEvent, FsEntryLicenseState> {
  FsEntryLicenseBloc({
    required this.driveId,
    required this.selectedItems,
    required ArweaveService arweave,
    required TurboUploadService turboUploadService,
    required DriveDao driveDao,
    required ProfileCubit profileCubit,
    required ArDriveCrypto crypto,
    required LicenseService licenseService,
    Platform platform = const LocalPlatform(),
  })  : _arweave = arweave,
        _turboUploadService = turboUploadService,
        _driveDao = driveDao,
        _profileCubit = profileCubit,
        _crypto = crypto,
        _licenseService = licenseService,
        super(const FsEntryLicenseLoadInProgress()) {
    if (selectedItems.isEmpty) {
      addError(Exception('selectedItems cannot be empty'));
    }

    on<FsEntryLicenseEvent>(_onEvent, transformer: restartable());
  }

  final String driveId;
  final List<ArDriveDataTableItem> selectedItems;

  LicenseCategory get selectedLicenseCategory =>
      categoryForm.control('licenseCategory').value;

  LicenseMeta _selectedLicenseMeta = udlLicenseDefault;
  LicenseMeta get selectedLicenseMeta => _selectedLicenseMeta;

  List<FileEntry>? filesToLicense;
  LicenseParams? licenseParams;

  final ArweaveService _arweave;
  final TurboUploadService _turboUploadService;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final ArDriveCrypto _crypto;
  final LicenseService _licenseService;

  final List<String> errorLog = [];

  /// Form getters
  FormGroup get categoryForm => _categoryForm;
  FormGroup get udlParamsForm => _udlParamsForm;
  FormGroup get ccTypeForm => _ccTypeForm;

  // Forms
  final _categoryForm = FormGroup({
    'licenseCategory': FormControl<LicenseCategory>(
      validators: [Validators.required],
      value: LicenseCategory.udl,
    ),
  });

  final _udlParamsForm = createUdlParamsForm();
  final _ccTypeForm = createCcTypeForm();

  Future<void> _onEvent(
    FsEntryLicenseEvent event,
    Emitter<FsEntryLicenseState> emit,
  ) async {
    if (event is FsEntryLicenseInitial) {
      await _handleInitial(event, emit);
    } else if (event is FsEntryLicenseSelect) {
      await _handleSelect(event, emit);
    } else if (event is FsEntryLicenseConfigurationSubmit) {
      await _handleConfigurationSubmit(event, emit);
    } else if (event is FsEntryLicenseReviewConfirm) {
      await _handleReviewConfirm(event, emit);
    } else if (event is FsEntryLicenseReviewBack) {
      _handleReviewBack(event, emit);
    } else if (event is FsEntryLicenseConfigurationBack) {
      _handleConfigurationBack(event, emit);
    } else if (event is FsEntryLicenseSuccessClose) {
      _handleSuccessClose(event, emit);
    } else if (event is FsEntryLicenseFailureTryAgain) {
      _handleFailureTryAgain(event, emit);
    } else {
      addError('Unsupported event: ${event.runtimeType}');
    }
  }

  Future<void> _handleInitial(
    FsEntryLicenseInitial event,
    Emitter<FsEntryLicenseState> emit,
  ) async {
    filesToLicense = await _enumerateFiles(items: selectedItems, emit: emit);
    if (filesToLicense!.isEmpty) {
      emit(const FsEntryLicenseNoFiles());
    } else {
      emit(const FsEntryLicenseSelecting());
    }
  }

  Future<void> _handleSelect(
    FsEntryLicenseSelect event,
    Emitter<FsEntryLicenseState> emit,
  ) async {
    emit(const FsEntryLicenseConfiguring());
  }

  Future<void> _handleConfigurationSubmit(
    FsEntryLicenseConfigurationSubmit event,
    Emitter<FsEntryLicenseState> emit,
  ) async {
    switch (selectedLicenseCategory) {
      case LicenseCategory.udl:
        _selectedLicenseMeta = udlLicenseDefault;
        licenseParams = udlFormToLicenseParams(udlParamsForm);
        break;
      case LicenseCategory.cc:
        _selectedLicenseMeta = ccTypeForm.control('ccTypeField').value;
        licenseParams = null;
        break;
      default:
        addError('Unsupported license category: $selectedLicenseCategory');
    }

    emit(const FsEntryLicenseReviewing());
  }

  Future<void> _handleReviewConfirm(
    FsEntryLicenseReviewConfirm event,
    Emitter<FsEntryLicenseState> emit,
  ) async {
    emit(const FsEntryLicenseLoadInProgress());
    try {
      final profile = _profileCubit.state as ProfileLoggedIn;
      await _licenseEntities(
        profile: profile,
        licenseMeta: _selectedLicenseMeta,
        licenseParams: licenseParams,
      );
      emit(const FsEntryLicenseSuccess());
    } catch (_, trace) {
      addError('Error licensing entities', trace);
      emit(const FsEntryLicenseFailure());
    }
  }

  void _handleReviewBack(
    FsEntryLicenseReviewBack event,
    Emitter<FsEntryLicenseState> emit,
  ) {
    // Every LicenseCategory has its own configure step
    licenseParams = null;
    emit(const FsEntryLicenseConfiguring());
  }

  void _handleConfigurationBack(
    FsEntryLicenseConfigurationBack event,
    Emitter<FsEntryLicenseState> emit,
  ) {
    emit(const FsEntryLicenseSelecting());
  }

  void _handleSuccessClose(
    FsEntryLicenseSuccessClose event,
    Emitter<FsEntryLicenseState> emit,
  ) {
    emit(const FsEntryLicenseComplete());
  }

  void _handleFailureTryAgain(
    FsEntryLicenseFailureTryAgain event,
    Emitter<FsEntryLicenseState> emit,
  ) {
    emit(const FsEntryLicenseReviewing());
  }

  Future<List<FileEntry>> _enumerateFiles({
    required List<ArDriveDataTableItem> items,
    required Emitter<FsEntryLicenseState> emit,
  }) async {
    final files = <FileEntry>[];

    Future<List<FileEntry>> enumerateFilesFromTree(
      FolderNode folderTree,
    ) async {
      final treeFiles = <FileEntry>[];

      treeFiles.addAll(folderTree.files.values);

      for (final subfolder in folderTree.subfolders) {
        final subfolderFiles = await enumerateFilesFromTree(subfolder);
        treeFiles.addAll(subfolderFiles);
      }

      return treeFiles;
    }

    for (final item in items) {
      if (item is FileDataTableItem) {
        final file = await _driveDao
            .fileById(driveId: driveId, fileId: item.id)
            .getSingle();
        files.add(file);
      } else if (item is FolderDataTableItem) {
        final folderTree = await _driveDao.getFolderTree(driveId, item.id);
        final subFiles = await enumerateFilesFromTree(folderTree);
        files.addAll(subFiles);
      } else {
        addError('Unsupported item type: ${item.runtimeType}');
      }
    }

    // Do not allow pinned files to be licensed
    return files.where((file) => file.pinnedDataOwnerAddress == null).toList();
  }

  Future<void> _licenseEntities({
    required ProfileLoggedIn profile,
    required LicenseMeta licenseMeta,
    LicenseParams? licenseParams,
  }) async {
    final licenseState = LicenseState(
      meta: licenseMeta,
      params: licenseParams,
    );

    final driveKey = await _driveDao.getDriveKey(driveId, profile.cipherKey);

    final licenseAssertionTxDataItems = <DataItem>[];
    final fileRevisionTxDataItems = <DataItem>[];

    await _driveDao.transaction(() async {
      for (var file in filesToLicense!) {
        final allRevisions = await _driveDao
            .oldestFileRevisionsByFileId(
              driveId: driveId,
              fileId: file.id,
            )
            .get();
        final dataTxIdsSet = allRevisions.map((rev) => rev.dataTxId).toSet();

        for (final dataTxId in dataTxIdsSet) {
          final licenseAssertionEntity = _licenseService.toEntity(
            licenseState: licenseState,
            dataTxId: dataTxId,
          )..ownerAddress = profile.walletAddress;

          final owner = await profile.wallet.getOwner();
          final appInfo = AppInfoServices().appInfo;
          final licenseAssertionDataItem = await licenseAssertionEntity
              .asPreparedDataItem(owner: owner, appInfo: appInfo);
          await licenseAssertionDataItem.sign(profile.wallet);
          licenseAssertionTxDataItems.add(licenseAssertionDataItem);

          licenseAssertionEntity.txId = licenseAssertionDataItem.id;

          await _driveDao.insertLicense(
            licenseAssertionEntity.toCompanion(
              fileId: file.id,
              driveId: driveId,
              licenseType: licenseMeta.licenseType,
            ),
          );
        }

        final latestLicenseAssertionTxId = licenseAssertionTxDataItems.last.id;
        file = file.copyWith(
            licenseTxId: Value(latestLicenseAssertionTxId),
            lastUpdated: DateTime.now());

        final fileEntity = file.asEntity();
        final fileKey = driveKey != null
            ? await _crypto.deriveFileKey(driveKey, file.id)
            : null;
        final fileDataItem = await _arweave.prepareEntityDataItem(
          fileEntity,
          profile.wallet,
          key: fileKey,
        );

        fileRevisionTxDataItems.add(fileDataItem);

        await _driveDao.writeToFile(file);
        fileEntity.txId = fileDataItem.id;

        await _driveDao.insertFileRevision(fileEntity.toRevisionCompanion(
          performedAction: RevisionAction.assertLicense,
        ));
      }
    });

    final dataItems = licenseAssertionTxDataItems + fileRevisionTxDataItems;
    if (_turboUploadService.useTurboUpload) {
      for (var dataItem in dataItems) {
        await _turboUploadService.postDataItem(
          dataItem: dataItem,
          wallet: profile.wallet,
        );
      }
    } else {
      final dataBundle = await _arweave.prepareDataBundleTx(
        await DataBundle.fromDataItems(
          items: dataItems,
        ),
        profile.wallet,
      );
      await _arweave.postTx(dataBundle);
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    errorLog.add(error.toString());
    super.onError(error, stackTrace);
  }
}
