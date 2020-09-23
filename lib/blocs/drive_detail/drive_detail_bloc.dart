import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:drive/entities/entities.dart';
import 'package:drive/models/models.dart';
import 'package:drive/services/services.dart';
import 'package:meta/meta.dart';
import 'package:moor/moor.dart';
import 'package:pedantic/pedantic.dart';
import 'package:rxdart/rxdart.dart';

import '../blocs.dart';

part 'drive_detail_event.dart';
part 'drive_detail_state.dart';

class DriveDetailBloc extends Bloc<DriveDetailEvent, DriveDetailState> {
  final String _driveId;
  final ProfileBloc _profileBloc;
  final UploadBloc _uploadBloc;
  final ArweaveService _arweave;
  final DriveDao _driveDao;

  StreamSubscription _folderSubscription;

  DriveDetailBloc(
      {@required String driveId,
      @required ArweaveService arweave,
      @required ProfileBloc profileBloc,
      @required UploadBloc uploadBloc,
      @required DriveDao driveDao})
      : _driveId = driveId,
        _arweave = arweave,
        _profileBloc = profileBloc,
        _uploadBloc = uploadBloc,
        _driveDao = driveDao,
        super(FolderLoadInProgress()) {
    if (driveId != null) add(OpenFolder(''));
  }

  @override
  Stream<DriveDetailState> mapEventToState(
    DriveDetailEvent event,
  ) async* {
    if (event is OpenFolder) {
      yield* _mapOpenFolderToState(event);
    } else if (event is OpenedFolder) {
      yield* _mapOpenedFolderToState(event);
    } else if (event is NewFolder) {
      yield* _mapNewFolderToState(event);
    } else if (event is UploadFile) yield* _mapUploadFileToState(event);
  }

  Stream<DriveDetailState> _mapOpenFolderToState(OpenFolder event) async* {
    unawaited(_folderSubscription?.cancel());

    _folderSubscription = Rx.combineLatest3(
      _driveDao.watchDrive(_driveId),
      _driveDao.watchFolder(_driveId, event.folderPath),
      _profileBloc.startWith(null),
      (drive, folderContents, _) => OpenedFolder(drive, folderContents),
    ).listen((event) => add(event));
  }

  Stream<DriveDetailState> _mapOpenedFolderToState(OpenedFolder event) async* {
    final userState = _profileBloc.state;

    yield FolderLoadSuccess(
      currentDrive: event.openedDrive,
      hasWritePermissions: userState is ProfileActive &&
          event.openedDrive.ownerAddress == userState.wallet.address,
      currentFolder: event.openedFolder,
    );
  }

  Stream<DriveDetailState> _mapNewFolderToState(NewFolder event) async* {
    final profile = _profileBloc as ProfileActive;
    final currentState = state as FolderLoadSuccess;
    final currentFolder = currentState.currentFolder.folder;

    final driveKey = currentState.currentDrive.privacy == DrivePrivacy.private
        ? await _driveDao.getDriveKey(_driveId, profile.cipherKey)
        : null;

    final newFolderId = await _driveDao.createNewFolder(
      _driveId,
      currentFolder.id,
      event.folderName,
      '${currentFolder.path}/${event.folderName}',
    );

    final folderTx = await _arweave.prepareEntityTx(
        FolderEntity(
          id: newFolderId,
          driveId: currentFolder.driveId,
          parentFolderId: currentFolder.id,
          name: event.folderName,
        ),
        profile.wallet,
        driveKey);

    await _arweave.postTx(folderTx);
  }

  Stream<DriveDetailState> _mapUploadFileToState(UploadFile event) async* {
    final profile = _profileBloc as ProfileActive;
    final currentState = state as FolderLoadSuccess;
    final currentFolder = currentState.currentFolder.folder;
    final drive = currentState.currentDrive;

    event.fileEntity
      ..driveId = _driveId
      ..parentFolderId = currentFolder.id;

    final driveKey = drive.privacy == DrivePrivacy.private
        ? await _driveDao.getDriveKey(_driveId, profile.cipherKey)
        : null;

    _uploadBloc.add(
      PrepareFileUpload(
        event.fileEntity,
        '${currentFolder.path}/${event.fileEntity.name}',
        event.fileStream,
        driveKey,
      ),
    );
  }
}
