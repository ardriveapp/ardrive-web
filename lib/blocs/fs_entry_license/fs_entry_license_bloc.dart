import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/license_assertion.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/services/license/license_types.dart';
import 'package:ardrive/services/license/licenses/udl.dart';
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
    'licenseType': FormControl<LicenseInfo>(
      validators: [Validators.required],
      value: udlLicenseInfo,
    ),
  });
  LicenseInfo get selectFormLicenseInfo =>
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

  LicenseParams? licenseParams;

  final ArweaveService _arweave;
  final TurboUploadService _turboUploadService;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final ArDriveCrypto _crypto;
  final LicenseService _licenseService;

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
        super(const FsEntryLicenseSelecting()) {
    if (selectedItems.isEmpty) {
      addError(Exception('selectedItems cannot be empty'));
    }

    if (selectedItems.any((item) => item is! FileDataTableItem)) {
      addError(Exception('selectedItems must only contain files'));
    }

    final profile = _profileCubit.state as ProfileLoggedIn;

    on<FsEntryLicenseEvent>(
      (event, emit) async {
        if (await _profileCubit.logoutIfWalletMismatch()) {
          emit(const FsEntryLicenseWalletMismatch());
          return;
        }

        if (event is FsEntryLicenseSelect) {
          if (selectFormLicenseInfo.hasParams) {
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
          if (selectFormLicenseInfo.licenseType == LicenseType.udl) {
            licenseParams = await udlFormToLicenseParams(udlForm);
          } else {
            addError(
                'Unsupported license configuration: ${selectFormLicenseInfo.licenseType}');
          }
          emit(const FsEntryLicenseReviewing());
        }

        if (event is FsEntryLicenseReviewBack) {
          if (selectFormLicenseInfo.hasParams) {
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
              licenseInfo: selectFormLicenseInfo,
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

    return UdlLicenseParams(
      licenseFeeAmount: licenseFeeAmount,
      licenseFeeCurrency: licenseFeeCurrency,
      commercialUse: commercialUse,
      derivations: derivations,
    );
  }

  Future<void> licenseEntities({
    required ProfileLoggedIn profile,
    required LicenseInfo licenseInfo,
    LicenseParams? licenseParams,
  }) async {
    final driveKey = await _driveDao.getDriveKey(driveId, profile.cipherKey);

    final licenseAssertionTxDataItems = <DataItem>[];
    final fileRevisionTxDataItems = <DataItem>[];

    final filesToLicense =
        selectedItems.whereType<FileDataTableItem>().toList();

    await _driveDao.transaction(() async {
      for (var fileToLicense in filesToLicense) {
        var file = await _driveDao
            .fileById(driveId: driveId, fileId: fileToLicense.id)
            .getSingle();

        final allReivisions = await _driveDao
            .oldestFileRevisionsByFileId(
              driveId: driveId,
              fileId: fileToLicense.id,
            )
            .get();
        final dataTxIdsSet = allReivisions.map((rev) => rev.dataTxId).toSet();

        for (final dataTxId in dataTxIdsSet) {
          final licenseAssertionEntity = _licenseService.toEntity(
            dataTxId: dataTxId,
            licenseInfo: licenseInfo,
            licenseParams: licenseParams,
          )..ownerAddress = profile.walletAddress;

          final licenseAssertionDataItem = await licenseAssertionEntity
              .asPreparedDataItem(owner: await profile.wallet.getOwner());
          await licenseAssertionDataItem.sign(profile.wallet);
          licenseAssertionTxDataItems.add(licenseAssertionDataItem);

          licenseAssertionEntity.txId = licenseAssertionDataItem.id;

          await _driveDao.insertLicenseAssertion(
            licenseAssertionEntity.toLicenseAssertionsCompanion(
              fileId: file.id,
              driveId: driveId,
              licenseType: licenseInfo.licenseType,
            ),
          );
        }

        final latestDataLicenseAssertionTxId =
            licenseAssertionTxDataItems.last.id;
        file = file.copyWith(
            licenseTxId: Value(latestDataLicenseAssertionTxId),
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
}
