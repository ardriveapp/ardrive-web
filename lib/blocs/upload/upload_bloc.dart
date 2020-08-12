import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';

import '../../repositories/repositories.dart';

part 'upload_event.dart';
part 'upload_state.dart';

class UploadBloc extends Bloc<UploadEvent, UploadState> {
  final DriveDao _driveDao;

  UploadBloc({@required DriveDao driveDao})
      : _driveDao = driveDao,
        super(UploadInitial());

  @override
  Stream<UploadState> mapEventToState(
    UploadEvent event,
  ) async* {
    if (event is UploadFileToNetwork)
      yield* _mapUploadFileToNetworkToState(event);
  }

  Stream<UploadState> _mapUploadFileToNetworkToState(
      UploadFileToNetwork event) async* {
    yield UploadInProgress();

    await _driveDao.createNewFileEntry(
      event.driveId,
      event.parentFolderId,
      event.fileName,
      event.filePath,
      event.fileSize,
    );
  }
}
