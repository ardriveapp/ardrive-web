import 'dart:async';

import 'package:ardrive/blocs/drive_detail/selected_item.dart';
import 'package:ardrive/models/models.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'fs_entry_activity_state.dart';

class FsEntryActivityCubit extends Cubit<FsEntryActivityState> {
  final String driveId;
  final SelectedItem? maybeSelectedItem;

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
      switch (selectedItem.getItemType()) {
        case SelectedItemType.Folder:
          _entrySubscription = _driveDao
              .latestFolderRevisionsByFolderIdWithTransactions(
                driveId: driveId,
                folderId: selectedItem.getID(),
              )
              .watch()
              .listen((r) => emit(
                  FsEntryActivitySuccess<FolderRevisionWithTransaction>(
                      revisions: r)));
          break;
        case SelectedItemType.File:
          _entrySubscription = _driveDao
              .latestFileRevisionsByFileIdWithTransactions(
                driveId: driveId,
                fileId: selectedItem.getID(),
              )
              .watch()
              .listen((r) => emit(
                  FsEntryActivitySuccess<FileRevisionWithTransactions>(
                      revisions: r)));
          break;

        default:
      }
    } else {
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

    print('Failed to load entity activity: $error $stackTrace');
  }

  @override
  Future<void> close() {
    _entrySubscription?.cancel();
    return super.close();
  }
}
