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
          .latestFolderRevisionsByFolderId(driveId, folderId)
          .watch()
          .listen((r) =>
              emit(FsEntryActivitySuccess<FolderRevision>(revisions: r)));
    } else if (fileId != null) {
      _entrySubscription = _driveDao
          .latestFileRevisionsByFileId(driveId, fileId)
          .watch()
          .listen(
              (r) => emit(FsEntryActivitySuccess<FileRevision>(revisions: r)));
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
