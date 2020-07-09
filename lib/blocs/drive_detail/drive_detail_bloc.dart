import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:drive/repositories/repositories.dart';
import 'package:meta/meta.dart';

part 'drive_detail_event.dart';
part 'drive_detail_state.dart';

class DriveDetailBloc extends Bloc<DriveDetailEvent, DriveDetailState> {
  final DriveDao _driveDao;

  StreamSubscription _driveSubscription;
  StreamSubscription _folderSubscription;

  DriveDetailBloc({@required String driveId, @required DriveDao driveDao})
      : this._driveDao = driveDao,
        super(DriveOpening()) {
    add(OpenDrive(driveId));
  }

  @override
  Stream<DriveDetailState> mapEventToState(
    DriveDetailEvent event,
  ) async* {
    if (event is OpenDrive)
      yield* _mapOpenDriveToState(event);
    else if (event is OpenedDrive)
      yield* _mapOpenedDriveToState(event);
    else if (event is OpenFolder)
      yield* _mapOpenFolderToState(event);
    else if (event is OpenedFolder) yield* _mapOpenedFolderToState(event);
  }

  Stream<DriveDetailState> _mapOpenDriveToState(OpenDrive event) async* {
    _driveSubscription?.cancel();
    _driveSubscription = _driveDao.watchDrive(event.driveId).listen(
      (drive) {
        if (drive != null) add(OpenedDrive(drive));
      },
    );
  }

  Stream<DriveDetailState> _mapOpenedDriveToState(OpenedDrive event) async* {
    // If we're not already opening or have opened a folder, open the root drive folder.
    if (!(state is FolderOpened || state is FolderOpening))
      add(OpenFolder(folderId: event.drive.rootFolderId));

    yield DriveOpened(openedDrive: event.drive);
  }

  Stream<DriveDetailState> _mapOpenFolderToState(OpenFolder event) async* {
    if (state is DriveOpened) {
      _folderSubscription?.cancel();

      final folderStream = event.folderId != null
          ? _driveDao.watchFolderWithContents(event.folderId)
          : _driveDao.watchFolderWithContentsAtPath(event.folderPath);

      _folderSubscription =
          folderStream.listen((folder) => add(OpenedFolder(folder)));
    }
  }

  Stream<DriveDetailState> _mapOpenedFolderToState(OpenedFolder event) async* {
    if (state is DriveOpened) {
      yield FolderOpened(
        openedDrive: (state as DriveOpened).openedDrive,
        openedFolder: event.openedFolder,
      );
    }
  }
}
