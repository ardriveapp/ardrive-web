import 'dart:async';

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'fs_entry_activity_state.dart';

class FsEntryActivityCubit extends Cubit<FsEntryActivityState> {
  final String driveId;
  final ArDriveDataTableItem? maybeSelectedItem;

  final DriveDao _driveDao;
  final ArweaveService _arweave;
  final ProfileCubit _profileCubit;

  StreamSubscription? _entrySubscription;

  /// Whether this device holds any of the drive's history. Once it does, a
  /// history read from the network is stale beside it and is dropped.
  bool _hasLocalDriveHistory = false;
  bool _networkDriveHistoryRequested = false;

  FsEntryActivityCubit({
    required this.driveId,
    this.maybeSelectedItem,
    required DriveDao driveDao,
    required ArweaveService arweave,
    required ProfileCubit profileCubit,
  })  : _driveDao = driveDao,
        _arweave = arweave,
        _profileCubit = profileCubit,
        super(FsEntryActivityInitial()) {
    final selectedItem = maybeSelectedItem;
    if (selectedItem != null) {
      switch (selectedItem.runtimeType) {
        case const (FolderDataTableItem):
          _entrySubscription = _driveDao
              .latestFolderRevisionsByFolderIdWithTransactions(
                driveId: driveId,
                folderId: selectedItem.id,
              )
              .watch()
              .listen((r) => emit(
                  FsEntryActivitySuccess<FolderRevisionWithTransaction>(
                      revisions: r)));
          break;
        case const (FileDataTableItem):
          _entrySubscription = _driveDao
              .latestFileRevisionsByFileIdWithLicenseAndTransactions(
                driveId: driveId,
                fileId: selectedItem.id,
              )
              .watch()
              .listen((r) => emit(FsEntryActivitySuccess<
                  FileRevisionWithLicenseAndTransactions>(revisions: r)));
          break;

        default:
          _entrySubscription = _driveDao
              .latestDriveRevisionsByDriveIdWithTransactions(driveId: driveId)
              .watch()
              .listen((r) {
            // Sync records a drive's creation before anything else, so no
            // revisions means it has not been synced here, not that nothing
            // happened to it. Its history is read from the network instead.
            if (r.isEmpty && !_hasLocalDriveHistory) {
              if (!_networkDriveHistoryRequested) {
                _networkDriveHistoryRequested = true;
                _loadDriveHistoryFromNetwork();
              }
              return;
            }

            _hasLocalDriveHistory = true;
            emit(
              FsEntryActivitySuccess<DriveRevisionWithTransaction>(
                revisions: r,
              ),
            );
          });
      }
    }
  }

  /// Reads the drive's own history from the network and shows it, newest
  /// first, the way a synced drive's is shown. Nothing is stored.
  Future<void> _loadDriveHistoryFromNetwork() async {
    List<DriveRevisionsCompanion>? revisions;

    try {
      final drive =
          await _driveDao.driveById(driveId: driveId).getSingleOrNull();

      if (drive != null) {
        DriveKey? driveKey;
        if (drive.isPrivate) {
          final profile = _profileCubit.state;
          driveKey = profile is ProfileLoggedIn
              ? await _driveDao.getDriveKey(driveId, profile.user.cipherKey)
              : await _driveDao.getDriveKeyFromMemory(driveId);
        }

        // A private drive without its key reads as nothing at all, so it is
        // not asked for.
        if (!drive.isPrivate || driveKey != null) {
          final entities = await _arweave.getDriveEntityRevisions(
            driveId,
            ownerAddress: drive.ownerAddress,
            driveKey: driveKey?.key,
            // Closing the panel or leaving the tab stops the reads.
            isCancelled: () => isClosed || _hasLocalDriveHistory,
          );

          if (entities != null) {
            revisions = driveRevisionsFromEntities(entities)
                .reversed
                .toList(growable: false);
          }
        }
      }
    } catch (e) {
      logger.w('Could not read the history of drive $driveId: $e');
    }

    // A sync that finished while this was reading has already put the real
    // history on screen.
    if (isClosed || _hasLocalDriveHistory) {
      return;
    }

    if (revisions == null || revisions.isEmpty) {
      emit(FsEntryActivityDriveNotSynced());
    } else {
      emit(
        FsEntryActivitySuccess<DriveRevisionsCompanion>(revisions: revisions),
      );
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    // Emitting after close throws, and that throw comes back here.
    if (!isClosed) {
      emit(FsEntryActivityFailure());
    }
    super.onError(error, stackTrace);

    logger.e('Failed to load entity activity', error, stackTrace);
  }

  @override
  Future<void> close() {
    _entrySubscription?.cancel();
    return super.close();
  }
}
