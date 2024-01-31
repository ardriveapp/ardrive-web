import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/license.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
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
  final String driveId;
  final List<ArDriveDataTableItem> selectedItems;

  final selectForm = FormGroup({
    'licenseType': FormControl<LicenseMeta>(
      validators: [Validators.required],
      value: udlLicenseMeta,
    ),
  });
  LicenseMeta get selectFormLicenseMeta =>
      selectForm.control('licenseType').value;

  final udlForm = FormGroup({
    'licenseFeeAmount': FormControl<String>(
      validators: [
        Validators.composeOR([
          Validators.pattern(
            r'^\d+\.?\d*$',
            validationMessage: 'Invalid amount',
          ),
          Validators.equals(''),
        ]),
      ],
    ),
    'licenseFeeCurrency': FormControl<UdlCurrency>(
      validators: [Validators.required],
      value: UdlCurrency.u,
    ),
    'commercialUse': FormControl<UdlCommercialUse>(
      validators: [Validators.required],
      value: UdlCommercialUse.unspecified,
    ),
    'derivations': FormControl<UdlDerivation>(
      validators: [Validators.required],
      value: UdlDerivation.unspecified,
    ),
  });

  List<FileEntry>? filesToLicense;
  LicenseParams? licenseParams;

  final ArweaveService _arweave;
  final TurboUploadService _turboUploadService;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final ArDriveCrypto _crypto;
  final LicenseService _licenseService;

  final List<String> errorLog = [];

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

    final profile = _profileCubit.state as ProfileLoggedIn;

    on<FsEntryLicenseEvent>(
      (event, emit) async {
        if (await _profileCubit.logoutIfWalletMismatch()) {
          emit(const FsEntryLicenseWalletMismatch());
          return;
        }

        if (event is FsEntryLicenseInitial) {
          filesToLicense =
              await enumerateFiles(items: selectedItems, emit: emit);
          if (filesToLicense!.isEmpty) {
            emit(const FsEntryLicenseNoFiles());
          } else {
            emit(const FsEntryLicenseSelecting());
          }
        }

        if (event is FsEntryLicenseSelect) {
          if (selectFormLicenseMeta.hasParams) {
            emit(const FsEntryLicenseConfiguring());
          } else {
            licenseParams = null;
            emit(const FsEntryLicenseReviewing());
          }
        }

        if (event is FsEntryLicenseConfigurationBack) {
          emit(const FsEntryLicenseSelecting());
        }

        if (event is FsEntryLicenseConfigurationSubmit) {
          if (selectFormLicenseMeta.licenseType == LicenseType.udl) {
            licenseParams = await udlFormToLicenseParams(udlForm);
          } else {
            addError(
                'Unsupported license configuration: ${selectFormLicenseMeta.licenseType}');
          }
          emit(const FsEntryLicenseReviewing());
        }

        if (event is FsEntryLicenseReviewBack) {
          if (selectFormLicenseMeta.hasParams) {
            licenseParams = null;
            emit(const FsEntryLicenseConfiguring());
          } else {
            emit(const FsEntryLicenseSelecting());
          }
        }

        if (event is FsEntryLicenseReviewConfirm) {
          emit(const FsEntryLicenseLoadInProgress());
          try {
            await licenseEntities(
              profile: profile,
              licenseMeta: selectFormLicenseMeta,
              licenseParams: licenseParams,
            );
            emit(const FsEntryLicenseSuccess());
          } catch (_, trace) {
            addError('Error licensing entities', trace);
            emit(const FsEntryLicenseFailure());
          }
        }

        if (event is FsEntryLicenseSuccessClose) {
          emit(const FsEntryLicenseComplete());
        }

        if (event is FsEntryLicenseFailureTryAgain) {
          emit(const FsEntryLicenseReviewing());
        }
      },
      transformer: restartable(),
    );
  }

  Future<UdlLicenseParams> udlFormToLicenseParams(FormGroup udlForm) async {
    final String? licenseFeeAmountString =
        udlForm.control('licenseFeeAmount').value;
    final double? licenseFeeAmount = licenseFeeAmountString == null
        ? null
        : double.tryParse(licenseFeeAmountString);

    final UdlCurrency licenseFeeCurrency =
        udlForm.control('licenseFeeCurrency').value;
    final UdlCommercialUse commercialUse =
        udlForm.control('commercialUse').value;
    final UdlDerivation derivations = udlForm.control('derivations').value;

    final profile = _profileCubit.state as ProfileLoggedIn;
    final String paymentAddress = profile.walletAddress;

    return UdlLicenseParams(
      licenseFeeAmount: licenseFeeAmount,
      licenseFeeCurrency: licenseFeeCurrency,
      commercialUse: commercialUse,
      derivations: derivations,
      paymentAddress: paymentAddress,
    );
  }

  Future<List<FileEntry>> enumerateFiles({
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

  Future<void> licenseEntities({
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

          final licenseAssertionDataItem = await licenseAssertionEntity
              .asPreparedDataItem(owner: await profile.wallet.getOwner());
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
