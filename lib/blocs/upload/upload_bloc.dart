import 'dart:async';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:drive/repositories/entities/entities.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../../repositories/repositories.dart';
import '../user/user_bloc.dart';

part 'upload_event.dart';
part 'upload_state.dart';

class UploadBloc extends Bloc<UploadEvent, UploadState> {
  final _uuid = Uuid();
  final UserBloc _userBloc;
  final DriveDao _driveDao;
  final ArweaveDao _arweaveDao;

  UploadBloc(
      {@required UserBloc userBloc,
      @required DriveDao driveDao,
      @required ArweaveDao arweaveDao})
      : _userBloc = userBloc,
        _driveDao = driveDao,
        _arweaveDao = arweaveDao,
        super(UploadInitial());

  @override
  Stream<UploadState> mapEventToState(
    UploadEvent event,
  ) async* {
    if (event is PrepareFileUpload)
      yield* _mapPrepareFileUploadToState(event);
    else if (event is UploadFileToNetwork)
      yield* _mapUploadFileToNetworkToState(event);
  }

  Stream<UploadState> _mapPrepareFileUploadToState(
      PrepareFileUpload event) async* {
    yield PreparingUpload();

    var fileId = await _driveDao.fileExistsInFolder(
      event.parentFolderId,
      event.fileName,
    );
    if (fileId == null) fileId = _uuid.v4();

    final wallet = (_userBloc.state as UserAuthenticated).userWallet;
    final transactions = <Transaction>[];

    if (await _driveDao.isDriveEmpty(event.driveId)) {
      final drive = await _driveDao.getDriveById(event.driveId);

      transactions.add(await _arweaveDao.prepareDriveEntityTx(
          DriveEntity(id: drive.id, rootFolderId: drive.rootFolderId), wallet));
    }

    if (await _driveDao.isFolderEmpty(event.parentFolderId)) {
      final parentFolder = await _driveDao.getFolderById(event.parentFolderId);

      transactions.add(await _arweaveDao.prepareFolderEntityTx(
        FolderEntity(
          id: parentFolder.id,
          driveId: event.driveId,
          parentFolderId: parentFolder.parentFolderId,
          name: parentFolder.name,
        ),
        wallet,
      ));
    }

    final uploadTxs = await _arweaveDao.prepareFileUploadTxs(
      FileEntity(
        id: fileId,
        driveId: event.driveId,
        parentFolderId: event.parentFolderId,
        name: event.fileName,
        size: event.fileSize,
      ),
      event.fileStream,
      wallet,
    );

    transactions.add(uploadTxs.entityTx);
    transactions.add(uploadTxs.dataTx);

    yield FileUploadReady(
      fileId,
      event.fileName,
      uploadTxs.dataTx.reward,
      event.fileSize,
      UploadFileToNetwork(
        fileId,
        event.driveId,
        event.parentFolderId,
        event.fileName,
        event.filePath,
        uploadTxs.dataTx.id,
        event.fileSize,
        transactions,
      ),
    );
  }

  Stream<UploadState> _mapUploadFileToNetworkToState(
      UploadFileToNetwork event) async* {
    await _arweaveDao.batchPostTxs(event.transactions);

    await _driveDao.writeFileEntry(
      event.fileId,
      event.driveId,
      event.parentFolderId,
      event.fileName,
      event.filePath,
      event.fileDataTxId,
      event.fileSize,
    );
  }
}
