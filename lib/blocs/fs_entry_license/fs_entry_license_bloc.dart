import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/license_assertion.dart';
import 'package:ardrive/models/license_assertion.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/services/license/license_types.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// ignore: depend_on_referenced_packages
import 'package:platform/platform.dart';

part 'fs_entry_license_event.dart';
part 'fs_entry_license_state.dart';

class FsEntryLicenseBloc
    extends Bloc<FsEntryLicenseEvent, FsEntryLicenseState> {
  final String driveId;
  final List<ArDriveDataTableItem> selectedItems;

  final ArweaveService _arweave;
  final TurboUploadService _turboUploadService;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;

  FsEntryLicenseBloc({
    required this.driveId,
    required this.selectedItems,
    required ArweaveService arweave,
    required TurboUploadService turboUploadService,
    required DriveDao driveDao,
    required ProfileCubit profileCubit,
    Platform platform = const LocalPlatform(),
  })  : _arweave = arweave,
        _turboUploadService = turboUploadService,
        _driveDao = driveDao,
        _profileCubit = profileCubit,
        super(const FsEntryLicenseLoadInProgress()) {
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

        if (event is FsEntryLicenseSubmit) {
          emit(const FsEntryLicenseLoadInProgress());

          await licenseEntities(
            profile: profile,
            licenseInfo: event.licenseInfo,
            licenseParams: event.licenseParams,
          );
          emit(const FsEntryLicenseSuccess());
        }
      },
      transformer: restartable(),
    );
  }

  Future<void> licenseEntities({
    required ProfileLoggedIn profile,
    required LicenseInfo licenseInfo,
    required LicenseParams licenseParams,
  }) async {
    final licenseAssertionTxDataItems = <DataItem>[];

    final filesToLicense =
        selectedItems.whereType<FileDataTableItem>().toList();

    await _driveDao.transaction(() async {
      for (var fileToLicense in filesToLicense) {
        var file = await _driveDao
            .fileById(driveId: driveId, fileId: fileToLicense.id)
            .getSingle();

        final licenseAssertionEntity = LicenseAssertionEntity(
          dataTxId: file.dataTxId,
          licenseTxId: licenseInfo.licenseTxId,
          additionalTags: licenseParams.toAdditionalTags(),
        );
        licenseAssertionEntity.ownerAddress = profile.walletAddress;

        final licenseAssertionDataItem =
            await licenseAssertionEntity.asPreparedDataItem(
          owner: licenseAssertionEntity.ownerAddress,
        );
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

        // TODO: Update FileEntry with latest license info?
        // await _driveDao.writeToFile(file);
      }
    });

    if (_turboUploadService.useTurboUpload) {
      for (var dataItem in licenseAssertionTxDataItems) {
        await _turboUploadService.postDataItem(
          dataItem: dataItem,
          wallet: profile.wallet,
        );
      }
    } else {
      final licenseTx = await _arweave.prepareDataBundleTx(
        await DataBundle.fromDataItems(
          items: licenseAssertionTxDataItems,
        ),
        profile.wallet,
      );
      await _arweave.postTx(licenseTx);
    }
  }
}
