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
        super(FsEntryLoadInProgress()) {
    if (folderId != null) {
      _entrySubscription = _driveDao.watchFolderById(driveId, folderId).listen(
            (f) => emit(
              FsEntryFolderLoadSuccess(
                name: f.name,
                lastUpdated: f.lastUpdated,
                dateCreated: f.dateCreated,
                folder: f,
              ),
            ),
          );
    } else if (fileId != null) {
      _entrySubscription = _driveDao.watchFileById(driveId, fileId).listen(
            (f) => emit(
              FsEntryFileLoadSuccess(
                  name: f.name,
                  lastUpdated: f.lastUpdated,
                  dateCreated: f.dateCreated,
                  file: f),
            ),
          );
    } else {
      _entrySubscription = _driveDao.watchDriveById(driveId).listen(
            (d) => emit(
              FsEntryDriveLoadSuccess(
                name: d.name,
                lastUpdated: d.lastUpdated,
                dateCreated: d.dateCreated,
                drive: d,
              ),
            ),
          );
    }
  }

  @override
  Future<void> close() {
    _entrySubscription?.cancel();
    return super.close();
  }
}
