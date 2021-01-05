import 'dart:async';

import 'package:ardrive/models/models.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

part 'fs_entry_info_state.dart';

class FsEntryInfoCubit extends Cubit<FsEntryInfoState> {
  final String driveId;
  final String folderId;
  final String fileId;

  final DriveDao _driveDao;

  StreamSubscription _entrySubscription;

  FsEntryInfoCubit(
      {@required this.driveId,
      this.folderId,
      this.fileId,
      @required DriveDao driveDao})
      : _driveDao = driveDao,
        super(FsEntryInfoInitial()) {
    if (folderId != null) {
      _entrySubscription =
          _driveDao.folderById(driveId, folderId).watchSingle().listen(
                (f) => emit(
                  FsEntryInfoSuccess<FolderEntry>(
                    name: f.name,
                    lastUpdated: f.lastUpdated,
                    dateCreated: f.dateCreated,
                    entry: f,
                  ),
                ),
              );
    } else if (fileId != null) {
      _entrySubscription =
          _driveDao.fileById(driveId, fileId).watchSingle().listen(
                (f) => emit(
                  FsEntryInfoSuccess<FileEntry>(
                    name: f.name,
                    lastUpdated: f.lastUpdated,
                    dateCreated: f.dateCreated,
                    entry: f,
                  ),
                ),
              );
    } else {
      _entrySubscription = _driveDao.driveById(driveId).watchSingle().listen(
            (d) => emit(
              FsEntryInfoSuccess<Drive>(
                name: d.name,
                lastUpdated: d.lastUpdated,
                dateCreated: d.dateCreated,
                entry: d,
              ),
            ),
          );
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(FsEntryInfoFailure());
    super.onError(error, stackTrace);
  }

  @override
  Future<void> close() {
    _entrySubscription?.cancel();
    return super.close();
  }
}
