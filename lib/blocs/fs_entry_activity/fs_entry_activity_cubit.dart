import 'dart:async';

import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'fs_entry_activity_state.dart';

class FsEntryActivityCubit extends Cubit<FsEntryActivityState> {
  final String driveId;
  final ArDriveDataTableItem? maybeSelectedItem;

  final DriveDao _driveDao;

  StreamSubscription? _entrySubscription;

  FsEntryActivityCubit({
    required this.driveId,
    this.maybeSelectedItem,
    required DriveDao driveDao,
  })  : _driveDao = driveDao,
        super(FsEntryActivityInitial()) {
    final selectedItem = maybeSelectedItem;
    if (selectedItem != null) {
      switch (selectedItem.runtimeType) {
        case FolderDataTableItem:
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
        case FileDataTableItem:
          _entrySubscription = _driveDao
              .latestFileRevisionsByFileIdWithTransactions(
                driveId: driveId,
                fileId: selectedItem.id,
              )
              .watch()
              .listen((r) => emit(
                  FsEntryActivitySuccess<FileRevisionWithTransactions>(
                      revisions: r)));
          break;

        default:
          _entrySubscription = _driveDao
              .latestDriveRevisionsByDriveIdWithTransactions(driveId: driveId)
              .watch()
              .listen(
                (r) => emit(
                  FsEntryActivitySuccess<DriveRevisionWithTransaction>(
                    revisions: r,
                  ),
                ),
              );
      }
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(FsEntryActivityFailure());
    super.onError(error, stackTrace);

    logger.e('Failed to load entity activity', error, stackTrace);
  }

  @override
  Future<void> close() {
    _entrySubscription?.cancel();
    return super.close();
  }
}
