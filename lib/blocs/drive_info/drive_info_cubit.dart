import 'dart:async';

import 'package:ardrive/models/models.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

part 'drive_info_state.dart';

class DriveInfoCubit extends Cubit<DriveInfoState> {
  final String driveId;
  final String folderId;
  final String fileId;

  final DriveDao _driveDao;

  StreamSubscription _entrySubscription;

  DriveInfoCubit(
      {@required this.driveId,
      this.folderId,
      this.fileId,
      @required DriveDao driveDao})
      : _driveDao = driveDao,
        super(DriveInfoLoadInProgress()) {
    if (folderId != null) {
      _entrySubscription = _driveDao.watchFolderById(driveId, folderId).listen(
          (f) => emit(DriveInfoFolderLoadSuccess(name: f.name, folder: f)));
    } else if (fileId != null) {
      _entrySubscription = _driveDao
          .watchFileById(driveId, fileId)
          .listen((f) => emit(DriveInfoFileLoadSuccess(name: f.name, file: f)));
    } else {
      _entrySubscription = _driveDao.watchDriveById(driveId).listen(
          (d) => emit(DriveInfoDriveLoadSuccess(name: d.name, drive: d)));
    }
  }

  @override
  Future<void> close() {
    _entrySubscription?.cancel();
    return super.close();
  }
}
