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
    // Its own handler, so nothing restarts a write under way, and a second
    // Confirm while one runs is dropped rather than queued.
    on<FsEntryLicenseReviewConfirm>(
      _handleReviewConfirm,
      transformer: droppable(),
    );
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

  /// The cost on the review, once read, and who pays for it.
  MetadataWriteCost? _cost;

  /// The signed write, kept from the first Confirm until every item has
  /// reached Turbo. A retry, after a failure or a refusal, sends only what
  /// has not been sent: never the same license twice as new items.
  _LicenseWrite? _write;

  /// A write is under way. Nothing else starts one, or reads the cost.
  var _writing = false;

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
      // Handled on its own; see the constructor.
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
  ///
  /// After part of a write reached Turbo, it prices what is left of it.
  Future<void> _readCost(Emitter<FsEntryLicenseState> emit) async {
    if (_writing) return;
    _cost = null;
    emit(const FsEntryLicenseReviewing());
    MetadataWriteCost cost;
    var pricingFailed = false;
    try {
      final profile = _profileCubit.state as ProfileLoggedIn;
      final items = _write?.remaining.map((step) => step.item).toList() ??
          (await _prepareWrite(profile: profile, sign: false)).items;
      cost = await _costReader.read(
        itemSizes: items.map(signedDataItemSize).toList(),
        wallet: profile.user.wallet,
        walletBalance: profile.user.walletBalance,
        refusedByTurbo: _refusedByTurbo,
      );
    } catch (error, trace) {
      // Not Turbo or the connection: the reader answers those itself.
      logger.e('Could not price the license', error, trace);
      cost = MetadataWriteCost(MetadataWriteCostReader.unavailable());
      pricingFailed = true;
    }
    _cost = cost;
    emit(FsEntryLicenseReviewing(
      summary: cost.summary,
      pricingFailed: pricingFailed,
    ));
  }

  Future<void> _handleReviewConfirm(
    FsEntryLicenseReviewConfirm event,
    Emitter<FsEntryLicenseState> emit,
  ) async {
    // Only what is free, or paid for the way the review showed. Nothing is
    // written while the price is unknown or the credits are short, and
    // nothing while a write is under way.
    final cost = _cost;
    if (_writing || cost == null || !cost.summary.isCovered) return;
    _writing = true;
    _cost = null;

    emit(const FsEntryLicenseLoadInProgress());
    try {
      final profile = _profileCubit.state as ProfileLoggedIn;
      await _licenseEntities(profile: profile, cost: cost);
      _writing = false;
      emit(const FsEntryLicenseSuccess());
    } catch (error, trace) {
      _writing = false;
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
    _cost = null;
    // A new license is a new write. Whatever of this one reached Turbo is
    // saved already.
    _write = null;
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

  /// The items licensing the files writes, file by file: a license
  /// assertion for each of the file's data transactions, then its new
  /// metadata.
  ///
  /// Unsigned, [sign] false, they are only measured: the review prices them
  /// before anything is signed. Signed, each comes with how to save it once
  /// it has been posted.
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
    String? lastAssertionId;

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
        if (!sign) {
          write.steps.add(_WriteStep.unsigned(licenseAssertionDataItem));
          continue;
        }

        await licenseAssertionDataItem.sign(signer);
        licenseAssertionEntity.txId = licenseAssertionDataItem.id;
        lastAssertionId = licenseAssertionDataItem.id;
        final license = licenseAssertionEntity.toCompanion(
          fileId: file.id,
          driveId: driveId,
          licenseType: licenseMeta.licenseType,
        );
        write.steps.add(_WriteStep(
          licenseAssertionDataItem,
          save: () => _driveDao.insertLicense(license),
        ));
      }

      final licensed = file.copyWith(
        // Unsigned items have no ID yet; one of the same length stands in.
        licenseTxId: Value(sign ? lastAssertionId : _unsignedTxIdStandIn),
        lastUpdated: DateTime.now(),
      );

      final fileEntity = licensed.asEntity();
      final fileKey = driveKey != null
          ? await _crypto.deriveFileKey(driveKey.key, licensed.id)
          : null;
      final fileDataItem = await _arweave.prepareEntityDataItem(
        fileEntity,
        wallet,
        key: fileKey,
        skipSignature: !sign,
      );
      if (!sign) {
        write.steps.add(_WriteStep.unsigned(fileDataItem));
        continue;
      }

      fileEntity.txId = fileDataItem.id;
      final revision = fileEntity.toRevisionCompanion(
        performedAction: RevisionAction.assertLicense,
      );
      write.steps.add(_WriteStep(
        fileDataItem,
        save: () async {
          await _driveDao.writeToFile(licensed);
          await _driveDao.insertFileRevision(revision);
        },
      ));
    }

    return write;
  }

  /// Sends what is left of the write, and saves each item once it is sent,
  /// so what is saved here is exactly what reached Turbo, whatever fails.
  Future<void> _licenseEntities({
    required ProfileLoggedIn profile,
    required MetadataWriteCost cost,
  }) async {
    final write = _write ??= await _prepareWrite(profile: profile, sign: true);

    if (_turboUploadService.useTurboUpload) {
      for (final step in write.remaining.toList()) {
        await _turboUploadService.postDataItem(
          dataItem: step.item,
          wallet: profile.user.wallet,
          // The wallets whose shared credits the review counted, as an
          // upload names them.
          headers: cost.headers,
        );
        write.posted++;
        await step.save();
      }
    } else {
      final rest = write.remaining.toList();
      final dataBundle = await _arweave.prepareDataBundleTx(
        await DataBundle.fromDataItems(
          items: [for (final step in rest) step.item],
        ),
        profile.user.wallet,
      );
      await _arweave.postTx(dataBundle);
      write.posted = write.steps.length;
      await _driveDao.transaction(() async {
        for (final step in rest) {
          await step.save();
        }
      });
    }

    _write = null;
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    errorLog.add(error.toString());
    super.onError(error, stackTrace);
  }
}

/// A transaction ID's length, for measuring items not yet signed.
final _unsignedTxIdStandIn = 'x' * 43;

/// One item of a write, and how to save it once it has been sent.
class _WriteStep {
  _WriteStep(this.item, {required this.save});

  /// Only measured, never sent.
  _WriteStep.unsigned(this.item) : save = _nothing;

  final DataItem item;
  final Future<void> Function() save;

  static Future<void> _nothing() async {}
}

class _LicenseWrite {
  final steps = <_WriteStep>[];

  /// How many of [steps], from the first, have been sent.
  var posted = 0;

  Iterable<_WriteStep> get remaining => steps.skip(posted);

  List<DataItem> get items => [for (final step in steps) step.item];
}
