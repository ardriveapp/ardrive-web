import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'folder_selector_event.dart';
part 'folder_selector_state.dart';

class FolderSelectorBloc
    extends Bloc<FolderSelectorEvent, FolderSelectorState> {
  final DriveDao driveDao;
  Drive? selectedDrive;
  List<Drive> drives = [];
  FolderSelectorBloc(
    this.driveDao,
  ) : super(LoadingDrivesState()) {
    on<FolderSelectorEvent>((event, emit) async {
      if (event is LoadDrivesEvent) {
        drives = await driveDao.allDrives().get();

        emit(SelectingDriveState(drives: drives));
      } else if (event is SelectDriveEvent) {
        emit(
          SelectingDriveState(
            drives: drives,
            selectedDrive: event.drive,
          ),
        );
      } else if (event is ConfirmDriveEvent) {
        final folderTree = await driveDao.getFolderTree(
            event.drive.id, event.drive.rootFolderId);

        selectedDrive = event.drive;

        emit(
          SelectingFolderState(
            selectedFolder: folderTree.folder,
            isRootFolder: true,
            folders: folderTree.subfolders.map((e) => e.folder).toList(),
          ),
        );
      } else if (event is SelectFolderEvent) {
        final folderTree =
            await driveDao.getFolderTree(event.folder.driveId, event.folder.id);
        FolderEntry? parentFolder;
        if (event.folder.parentFolderId != null) {
          parentFolder = await driveDao
              .folderById(folderId: event.folder.parentFolderId!)
              .getSingle();
        }

        emit(
          SelectingFolderState(
            isRootFolder: event.folder.id == selectedDrive!.rootFolderId,
            parentFolder: parentFolder,
            selectedFolder: event.folder,
            folders: folderTree.subfolders.map((e) => e.folder).toList(),
          ),
        );
      } else if (event is ConfirmFolderEvent) {
        emit(FolderSelectedState(event.folder.id, event.folder.driveId));
      }
    });
  }
}
