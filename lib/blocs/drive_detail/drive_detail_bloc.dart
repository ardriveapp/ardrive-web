import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:drive/repositories/repositories.dart';
import 'package:meta/meta.dart';
import 'package:moor/moor.dart';
import 'package:pedantic/pedantic.dart';
import 'package:rxdart/rxdart.dart';

import '../blocs.dart';

part 'drive_detail_event.dart';
part 'drive_detail_state.dart';

class DriveDetailBloc extends Bloc<DriveDetailEvent, DriveDetailState> {
  final String _driveId;
  final UserBloc _userBloc;
  final UploadBloc _uploadBloc;
  final ArweaveDao _arweaveDao;
  final DriveDao _driveDao;

  StreamSubscription _folderSubscription;

  DriveDetailBloc(
      {@required String driveId,
      @required ArweaveDao arweaveDao,
      @required UserBloc userBloc,
      @required UploadBloc uploadBloc,
      @required DriveDao driveDao})
      : _driveId = driveId,
        _arweaveDao = arweaveDao,
        _userBloc = userBloc,
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
      _userBloc.startWith(null),
      (drive, folderContents, _) => OpenedFolder(drive, folderContents),
    ).listen((event) => add(event));
  }

  Stream<DriveDetailState> _mapOpenedFolderToState(OpenedFolder event) async* {
    final userState = _userBloc.state;

    yield FolderLoadSuccess(
      currentDrive: event.openedDrive,
      hasWritePermissions: userState is UserAuthenticated &&
          event.openedDrive.ownerAddress == userState.userWallet.address,
      currentFolder: event.openedFolder,
    );
  }

  Stream<DriveDetailState> _mapNewFolderToState(NewFolder event) async* {
    final currentFolder = (state as FolderLoadSuccess).currentFolder.folder;

    final newFolderId = await _driveDao.createNewFolder(
      _driveId,
      currentFolder.id,
      event.folderName,
      '${currentFolder.path}/${event.folderName}',
    );

    final wallet = (_userBloc.state as UserAuthenticated).userWallet;

    final folderTx = await _arweaveDao.prepareEntityTx(
        FolderEntity(
          id: newFolderId,
          driveId: currentFolder.driveId,
          parentFolderId: currentFolder.id,
          name: event.folderName,
        ),
        wallet,
        await deriveDriveKey(wallet, _driveId, 'A?WgmN8gF%H9>A/~'));
    await _arweaveDao.postTx(folderTx);
  }

  Stream<DriveDetailState> _mapUploadFileToState(UploadFile event) async* {
    final currentFolder = (state as FolderLoadSuccess).currentFolder.folder;
    event.fileEntity
      ..driveId = _driveId
      ..parentFolderId = currentFolder.id;

    final wallet = (_userBloc.state as UserAuthenticated).userWallet;

    _uploadBloc.add(
      PrepareFileUpload(
        event.fileEntity,
        '${currentFolder.path}/${event.fileEntity.name}',
        event.fileStream,
        await deriveDriveKey(
            wallet, event.fileEntity.driveId, 'A?WgmN8gF%H9>A/~'),
      ),
    );
  }
}
