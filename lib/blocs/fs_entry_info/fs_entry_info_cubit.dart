import 'dart:async';

import 'package:ardrive/models/models.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'fs_entry_info_state.dart';

class FsEntryInfoCubit extends Cubit<FsEntryInfoState> {
  final String driveId;
  final SelectedItem? maybeSelectedItem;

  final DriveDao _driveDao;

  StreamSubscription? _entrySubscription;

  FsEntryInfoCubit({
    required this.driveId,
    this.maybeSelectedItem,
    required DriveDao driveDao,
  })  : _driveDao = driveDao,
        super(FsEntryInfoInitial()) {
    final selectedItem = maybeSelectedItem;
    if (selectedItem != null) {
      switch (selectedItem.runtimeType) {
        case SelectedFolder:
          _entrySubscription = _driveDao
              .getFolderTree(driveId, selectedItem.id)
              .asStream()
              .listen(
                (f) => emit(
                  FsEntryInfoSuccess<FolderNode>(
                    name: f.folder.name,
                    lastUpdated: f.folder.lastUpdated,
                    dateCreated: f.folder.dateCreated,
                    entry: f,
                  ),
                ),
              );
          break;
        case SelectedFile:
          _entrySubscription = _driveDao
              .fileById(driveId: driveId, fileId: selectedItem.id)
              .watchSingle()
              .listen(
                (f) => emit(
                  FsEntryInfoSuccess<FileEntry>(
                    name: f.name,
                    lastUpdated: f.lastUpdated,
                    dateCreated: f.dateCreated,
                    entry: f,
                  ),
                ),
              );
          break;
        default:
      }
    } else {
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
          emit(
            FsEntryDriveInfoSuccess(
              name: d.name,
              lastUpdated: d.lastUpdated,
              dateCreated: d.dateCreated,
              drive: d,
              rootFolderRevision: rootFolderRevision,
              rootFolderTree: rootFolderTree,
            ),
          );
        },
      );
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(FsEntryInfoFailure());
    super.onError(error, stackTrace);

    print('Failed to load entity info: $error $stackTrace');
  }

  @override
  Future<void> close() {
    _entrySubscription?.cancel();
    return super.close();
  }
}
