import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:drive/repositories/repositories.dart';
import 'package:meta/meta.dart';

part 'drive_detail_event.dart';
part 'drive_detail_state.dart';

class DriveDetailBloc extends Bloc<DriveDetailEvent, DriveDetailState> {
  DriveDetailBloc()
      : super(
          DriveDetailFolderOpenSuccess(
            selectedFolderId: '123',
            selectedFolderPathSegments: [
              DrivePathSegment(folderId: '123', folderName: 'Personal'),
              DrivePathSegment(folderId: '124', folderName: 'Documents'),
            ],
            subfolders: [
              Folder(name: 'Documents'),
              Folder(name: 'Pictures'),
            ],
            files: [
              File(name: 'cat.png'),
              File(name: 'dog.png'),
            ],
          ),
        );

  @override
  Stream<DriveDetailState> mapEventToState(
    DriveDetailEvent event,
  ) async* {
    if (event is OpenedFolder) {
      yield DriveDetailFolderOpening(selectedFolderId: event.folderId);
      yield DriveDetailFolderOpenSuccess(
        selectedFolderId: event.folderId,
        selectedFolderPathSegments: [
          DrivePathSegment(folderId: '123', folderName: 'Personal'),
          DrivePathSegment(folderId: '124', folderName: 'Documents'),
        ],
      );
    }
  }
}
