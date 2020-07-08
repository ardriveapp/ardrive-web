import 'package:bloc/bloc.dart';
import 'package:drive/repositories/repositories.dart';
import 'folder_event.dart';
import 'folder_state.dart';

class FolderBloc extends Bloc<FolderEvent, FolderState> {
  FolderBloc()
      : super(
          FolderLoadSuccess(
            [
              Folder(name: 'Documents'),
              Folder(name: 'Pictures'),
            ],
            [
              File(name: 'cat.png'),
              File(name: 'dog.png'),
            ],
          ),
        );

  @override
  Stream<FolderState> mapEventToState(FolderEvent event) async* {
    if (event is SubfolderAdded) yield* _mapAddSubfolderToState(event);
  }

  Stream<FolderState> _mapAddSubfolderToState(SubfolderAdded event) async* {
    if (state is FolderLoadSuccess) {
      final oldState = state as FolderLoadSuccess;

      final List<Folder> updatedSubfolders = List.from(oldState.subfolders)
        ..add(event.subfolder);

      yield FolderLoadSuccess(updatedSubfolders, oldState.files);
      // write to repo
    }
  }
}
