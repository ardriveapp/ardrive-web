import 'dart:async';

import 'package:ardrive/entities/license_assertion.dart';
import 'package:ardrive/entities/license_data_bundle.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:async/async.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'fs_entry_info_state.dart';

class FsEntryInfoCubit extends Cubit<FsEntryInfoState> {
  final String driveId;
  final ArDriveDataTableItem? maybeSelectedItem;

  final DriveDao _driveDao;
  final ArweaveService _arweave;
  final LicenseService _licenseService;

  StreamSubscription? _entrySubscription;

  FsEntryInfoCubit({
    required this.driveId,
    this.maybeSelectedItem,
    required DriveDao driveDao,
    required ArweaveService arweave,
    required LicenseService licenseService,
    bool isSharedFile = false,
  })  : _driveDao = driveDao,
        _arweave = arweave,
        _licenseService = licenseService,
        super(FsEntryInfoInitial()) {
    final selectedItem = maybeSelectedItem;
    if (selectedItem != null) {
      switch (selectedItem.runtimeType) {
        case FolderDataTableItem:
          _entrySubscription = _driveDao
              .getFolderTree(driveId, selectedItem.id)
              .asStream()
              .listen(
            (f) async {
              final metadataTxId = await _driveDao
                  .latestFolderRevisionByFolderId(
                      driveId: driveId, folderId: selectedItem.id)
                  .getSingle();

              emit(
                FsEntryInfoSuccess<FolderNode>(
                  name: f.folder.name,
                  lastUpdated: f.folder.lastUpdated,
                  dateCreated: f.folder.dateCreated,
                  entry: f,
                  metadataTxId: metadataTxId.metadataTxId,
                ),
              );
            },
          );
          break;
        case FileDataTableItem:
          _entrySubscription = _driveDao
              .fileById(driveId: driveId, fileId: selectedItem.id)
              .watchSingle()
              .listen(
            (f) async {
              final latestRevision = await _driveDao
                  .latestFileRevisionByFileId(
                      driveId: driveId, fileId: selectedItem.id)
                  .getSingle();

              LicenseState? licenseState;
              if (latestRevision.licenseTxId != null) {
                if (!isSharedFile) {
                  // First check if it is already synced to the local db
                  final license = await _driveDao
                      .licenseByTxId(tx: latestRevision.licenseTxId!)
                      .getSingleOrNull();

                  if (license != null) {
                    final companion = license.toCompanion(true);
                    licenseState = _licenseService.fromCompanion(companion);
                  }
                }
                // Othewise try to fetch it
                licenseState ??= await _fetchLicenseForRevision(latestRevision);
              }

              emit(FsEntryFileInfoSuccess(
                name: f.name,
                lastUpdated: f.lastUpdated,
                dateCreated: f.dateCreated,
                entry: f,
                metadataTxId: latestRevision.metadataTxId,
                licenseState: licenseState,
              ));
            },
          );
          break;
        default:
          _entrySubscription = _driveDao
              .driveById(
                driveId: driveId,
              )
              .watchSingle()
              .listen(
            (d) async {
              final rootFolderRevision = await _driveDao
                  .latestFolderRevisionByFolderId(
                    folderId: d.rootFolderId,
                    driveId: d.id,
                  )
                  .getSingle();
              final rootFolderTree =
                  await _driveDao.getFolderTree(d.id, d.rootFolderId);
              final metadataTxId = await _driveDao
                  .latestDriveRevisionByDriveId(driveId: driveId)
                  .getSingle();

              emit(
                FsEntryDriveInfoSuccess(
                  name: d.name,
                  lastUpdated: d.lastUpdated,
                  dateCreated: d.dateCreated,
                  drive: d,
                  rootFolderRevision: rootFolderRevision,
                  rootFolderTree: rootFolderTree,
                  metadataTxId: metadataTxId.metadataTxId,
                ),
              );
            },
          );
      }
    }
  }

  Future<LicenseState?> _fetchLicenseForRevision(FileRevision revision) async {
    final isAssertion = revision.licenseTxId != revision.dataTxId;
    if (isAssertion) {
      final licenseTx = (await _arweave
              .getLicenseAssertions([revision.licenseTxId!]).firstOrNull)
          ?.firstOrNull;
      if (licenseTx != null) {
        final licenseEntity = LicenseAssertionEntity.fromTransaction(licenseTx);
        return _licenseService.fromAssertionEntity(licenseEntity);
      }
    } else {
      final licenseTx = (await _arweave
              .getLicenseDataBundled([revision.licenseTxId!]).firstOrNull)
          ?.firstOrNull;
      if (licenseTx != null) {
        final licenseDataBundleEntity =
            LicenseDataBundleEntity.fromTransaction(licenseTx);
        return _licenseService.fromBundleEntity(licenseDataBundleEntity);
      }
    }
    return null;
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(FsEntryInfoFailure());
    super.onError(error, stackTrace);

    logger.e('Failed to load entity info', error, stackTrace);
  }

  @override
  Future<void> close() {
    _entrySubscription?.cancel();
    return super.close();
  }
}
