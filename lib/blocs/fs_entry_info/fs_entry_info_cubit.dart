import 'dart:async';

import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'fs_entry_info_state.dart';

class FsEntryInfoCubit extends Cubit<FsEntryInfoState> {
  final String driveId;
  final ArDriveDataTableItem? maybeSelectedItem;

  final DriveDao _driveDao;
  final LicenseService _licenseService;

  StreamSubscription? _entrySubscription;

  FsEntryInfoCubit({
    required this.driveId,
    this.maybeSelectedItem,
    required DriveDao driveDao,
    required LicenseService licenseService,
    bool isSharedFile = false,
    // Supplied in the case isSharedFile == true
    List<FileRevision>? maybeRevisions,
    LicenseState? maybeLicenseState,
  })  : _driveDao = driveDao,
        _licenseService = licenseService,
        super(FsEntryInfoInitial()) {
    final selectedItem = maybeSelectedItem;
    if (selectedItem != null) {
      switch (selectedItem.runtimeType) {
        case const (FolderDataTableItem):
          _entrySubscription = _driveDao
              .getFolderTree(driveId, selectedItem.id)
              .asStream()
              .listen(
            (f) async {
              if (isClosed) {
                return;
              }

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
        case const (FileDataTableItem):
          fileHandler(
            String id, {
            required String name,
            required DateTime lastUpdated,
            required DateTime dateCreated,
          }) async {
            // Revision must either come from DB (preferred) or [SharedFileCubit]
            final latestRevision = await _driveDao
                    .latestFileRevisionByFileId(driveId: driveId, fileId: id)
                    .getSingleOrNull() ??
                maybeRevisions!.first;

            LicenseState? licenseState;
            // Prefer unconfirmed LicenseState from the DB...
            if (latestRevision.licenseTxId != null) {
              final license = await _driveDao
                  .licenseByTxId(tx: latestRevision.licenseTxId!)
                  .getSingleOrNull();

              if (license != null) {
                final companion = license.toCompanion(true);
                licenseState = _licenseService.fromCompanion(companion);
              } else {
                // ...fall back to license fetched from [SharedFileCubit] if available
                licenseState ??= maybeLicenseState;
                // License not yet mined?
                licenseState ??= const LicenseState(
                  meta: LicenseMeta(
                    licenseType: LicenseType.unknown,
                    licenseDefinitionTxId: '',
                    name: 'Pending',
                    shortName: '...',
                  ),
                );
              }
            }

            emit(FsEntryFileInfoSuccess(
              name: name,
              lastUpdated: lastUpdated,
              dateCreated: dateCreated,
              metadataTxId: latestRevision.metadataTxId,
              licenseState: licenseState,
            ));
          }
          if (isSharedFile) {
            selectedItem is FileDataTableItem;
            fileHandler(
              selectedItem.id,
              name: selectedItem.name,
              lastUpdated: selectedItem.lastUpdated,
              dateCreated: selectedItem.dateCreated,
            );
          } else {
            _entrySubscription = _driveDao
                .fileById(fileId: selectedItem.id)
                .watchSingle()
                .listen(
                  (fileEntry) => fileHandler(
                    fileEntry.id,
                    name: fileEntry.name,
                    lastUpdated: fileEntry.lastUpdated,
                    dateCreated: fileEntry.dateCreated,
                  ),
                );
          }
          break;
        default:
          _entrySubscription = _driveDao
              .driveById(
                driveId: driveId,
              )
              .watchSingle()
              .listen(
            (d) async {
              if (isClosed) {
                return;
              }

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
