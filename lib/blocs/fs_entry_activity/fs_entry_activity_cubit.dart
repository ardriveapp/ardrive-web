import 'dart:async';

import 'package:ardrive/models/models.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

part 'fs_entry_activity_state.dart';

class FsEntryActivityCubit extends Cubit<FsEntryActivityState> {
  final String driveId;
  final String folderId;
  final String fileId;

  final DriveDao _driveDao;

  StreamSubscription _entrySubscription;

  FsEntryActivityCubit({
    @required this.driveId,
    this.folderId,
    this.fileId,
    @required DriveDao driveDao,
  })  : _driveDao = driveDao,
        super(FsEntryActivityInitial()) {
    if (folderId != null) {
      _entrySubscription = _driveDao
          .latestFolderRevisionsByFolderIdWithTransactions(
              driveId: driveId, folderId: folderId)
          .watch()
          .listen((r) => emit(
              FsEntryActivitySuccess<FolderRevisionWithTransaction>(
                  revisions: r)));
    } else if (fileId != null) {
      _entrySubscription = _driveDao
          .latestFileRevisionsByFileIdWithTransactions(
              driveId: driveId, fileId: fileId)
          .watch()
          .listen((r) => emit(
              FsEntryActivitySuccess<FileRevisionWithTransactions>(
                  revisions: r)));
    } else if (driveId != null) {
      _entrySubscription = _driveDao
          .latestDriveRevisionsByDriveIdWithTransactions(driveId: driveId)
          .watch()
          .listen(
            (r) => emit(FsEntryActivitySuccess<DriveRevisionWithTransaction>(
                revisions: r)),
          );
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(FsEntryActivityFailure());
    super.onError(error, stackTrace);
  }

  @override
  Future<void> close() {
    _entrySubscription?.cancel();
    return super.close();
  }
}
