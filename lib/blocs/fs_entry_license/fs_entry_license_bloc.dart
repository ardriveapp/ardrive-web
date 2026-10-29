import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/models/upload_review_summary.dart';
import 'package:ardrive/core/upload/metadata_write_cost.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/forms/cc.dart';
import 'package:ardrive/models/forms/udl.dart';
import 'package:ardrive/models/license.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
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
    required MetadataWriteCostReader costReader,
    Platform platform = const LocalPlatform(),
  })  : _arweave = arweave,
        _costReader = costReader,
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
  final MetadataWriteCostReader _costReader;

  /// The cost on the review, once read.
  UploadReviewSummary? _summary;

  /// Turbo refused a write as not paid for, so it is not free again whatever
  /// the allowance says.
  var _refusedByTurbo = false;

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
      await _readCost(emit);
    } else if (event is FsEntryLicenseCostRefresh) {
      await _readCost(emit);
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
        final LicenseMeta? ccLicenseMeta =
            ccTypeForm.control('ccTypeField').value;
        // No type is preselected, and Next stays disabled until one is
        // picked. If this is reached anyway, stay on this step.
        if (ccLicenseMeta == null) return;
        _selectedLicenseMeta = ccLicenseMeta;
        licenseParams = null;
        break;
      default:
        addError('Unsupported license category: $selectedLicenseCategory');
    }

    await _readCost(emit);
  }

  /// Shows the review, and reads what writing the license costs: the size of
  /// the items it writes, priced the way an upload is.
  Future<void> _readCost(Emitter<FsEntryLicenseState> emit) async {
    _summary = null;
    emit(const FsEntryLicenseReviewing());
    UploadReviewSummary summary;
    try {
      final profile = _profileCubit.state as ProfileLoggedIn;
      final write = await _prepareWrite(profile: profile, sign: false);
      summary = await _costReader.read(
        itemSizes: write.items.map(signedDataItemSize).toList(),
        wallet: profile.user.wallet,
        walletBalance: profile.user.walletBalance,
        refusedByTurbo: _refusedByTurbo,
      );
    } catch (error, trace) {
      logger.e('Could not price the license', error, trace);
      summary = MetadataWriteCostReader.unavailable();
    }
    _summary = summary;
    emit(FsEntryLicenseReviewing(summary: summary));
  }

  Future<void> _handleReviewConfirm(
    FsEntryLicenseReviewConfirm event,
    Emitter<FsEntryLicenseState> emit,
  ) async {
    // Only what is free, or paid for the way the review showed. Nothing is
    // written while the price is unknown or the credits are short.
    if (_summary?.isCovered != true) return;

    emit(const FsEntryLicenseLoadInProgress());
    try {
      final profile = _profileCubit.state as ProfileLoggedIn;
      await _licenseEntities(profile: profile);
      emit(const FsEntryLicenseSuccess());
    } catch (error, trace) {
      logger.e('Error licensing entities', error, trace);
      if (isTurboPaymentError(error)) {
        // Back to the review, with the balance read again and Add credits.
        _refusedByTurbo = true;
        await _readCost(emit);
        return;
      }
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
    _summary = null;
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
        final file = await _driveDao.fileById(fileId: item.id).getSingle();
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

  /// The items licensing the files writes: for each file, a license
  /// assertion for each of its data transactions, then its new metadata.
  ///
  /// Unsigned, [sign] false, they are only measured: the review prices them
  /// before anything is signed. Signed, they come with the rows to save once
  /// they are posted.
  Future<_LicenseWrite> _prepareWrite({
    required ProfileLoggedIn profile,
    required bool sign,
  }) async {
    final licenseMeta = _selectedLicenseMeta;
    final licenseState = LicenseState(
      meta: licenseMeta,
      params: licenseParams,
    );
    final wallet = profile.user.wallet;
    final driveKey =
        await _driveDao.getDriveKey(driveId, profile.user.cipherKey);
    final owner = await wallet.getOwner();
    final appInfo = AppInfoServices().appInfo;
    final signer = ArweaveSigner(wallet);
    final write = _LicenseWrite();

    for (var file in filesToLicense!) {
      final allRevisions = await _driveDao
          .oldestFileRevisionsByFileId(driveId: driveId, fileId: file.id)
          .get();
      final dataTxIdsSet = allRevisions.map((rev) => rev.dataTxId).toSet();

      for (final dataTxId in dataTxIdsSet) {
        final licenseAssertionEntity = _licenseService.toEntity(
          licenseState: licenseState,
          dataTxId: dataTxId,
        )..ownerAddress = profile.user.walletAddress;

        final licenseAssertionDataItem = await licenseAssertionEntity
            .asPreparedDataItem(owner: owner, appInfo: appInfo);
        write.assertions.add(licenseAssertionDataItem);
        if (!sign) continue;

        await licenseAssertionDataItem.sign(signer);
        licenseAssertionEntity.txId = licenseAssertionDataItem.id;
        write.licenses.add(
          licenseAssertionEntity.toCompanion(
            fileId: file.id,
            driveId: driveId,
            licenseType: licenseMeta.licenseType,
          ),
        );
      }

      file = file.copyWith(
        // Unsigned items have no ID yet; one of the same length stands in.
        licenseTxId:
            Value(sign ? write.assertions.last.id : _unsignedTxIdStandIn),
        lastUpdated: DateTime.now(),
      );

      final fileEntity = file.asEntity();
      final fileKey = driveKey != null
          ? await _crypto.deriveFileKey(driveKey.key, file.id)
          : null;
      final fileDataItem = await _arweave.prepareEntityDataItem(
        fileEntity,
        wallet,
        key: fileKey,
        skipSignature: !sign,
      );
      write.fileItems.add(fileDataItem);
      if (!sign) continue;

      fileEntity.txId = fileDataItem.id;
      write.files.add(file);
      write.revisions.add(fileEntity.toRevisionCompanion(
        performedAction: RevisionAction.assertLicense,
      ));
    }

    return write;
  }

  Future<void> _licenseEntities({required ProfileLoggedIn profile}) async {
    final write = await _prepareWrite(profile: profile, sign: true);

    if (_turboUploadService.useTurboUpload) {
      for (var dataItem in write.items) {
        await _turboUploadService.postDataItem(
          dataItem: dataItem,
          wallet: profile.user.wallet,
        );
      }
    } else {
      final dataBundle = await _arweave.prepareDataBundleTx(
        await DataBundle.fromDataItems(
          items: write.items,
        ),
        profile.user.wallet,
      );
      await _arweave.postTx(dataBundle);
    }

    // Saved once posted, so a refused write leaves no license behind that
    // was never written.
    await _driveDao.transaction(() async {
      for (final license in write.licenses) {
        await _driveDao.insertLicense(license);
      }
      for (var i = 0; i < write.files.length; i++) {
        await _driveDao.writeToFile(write.files[i]);
        await _driveDao.insertFileRevision(write.revisions[i]);
      }
    });
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    errorLog.add(error.toString());
    super.onError(error, stackTrace);
  }
}

/// A transaction ID's length, for measuring items not yet signed.
final _unsignedTxIdStandIn = 'x' * 43;

class _LicenseWrite {
  final assertions = <DataItem>[];
  final fileItems = <DataItem>[];
  final licenses = <LicensesCompanion>[];
  final files = <FileEntry>[];
  final revisions = <FileRevisionsCompanion>[];

  List<DataItem> get items => [...assertions, ...fileItems];
}
