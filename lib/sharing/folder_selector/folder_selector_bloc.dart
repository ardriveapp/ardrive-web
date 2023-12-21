import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

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

        emit(SelectingFolderState(folders: folderTree.getRecursiveFolders()));
      } else if (event is SelectFolderEvent) {
        final folders = (state as SelectingFolderState).folders;
        emit(SelectingFolderState(
          folders: folders,
          selectedFolder: event.folder,
        ));
      } else if (event is ConfirmFolderEvent) {
        emit(FolderSelectedState(event.folder.id, event.folder.driveId));
      }
    });
  }
}
