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

    final fileEntity = event.fileEntity;

    var existingFileId = await _driveDao.fileExistsInFolder(
      fileEntity.parentFolderId,
      fileEntity.name,
    );
    event.fileEntity.id = existingFileId ?? _uuid.v4();

    final wallet = (_userBloc.state as UserAuthenticated).userWallet;
    final transactions = <Transaction>[];

    if (await _driveDao.isDriveEmpty(fileEntity.driveId)) {
      final drive = await _driveDao.getDriveById(fileEntity.driveId);

      transactions.add(await _arweaveDao.prepareDriveEntityTx(
          DriveEntity(id: drive.id, rootFolderId: drive.rootFolderId), wallet));
    }

    if (await _driveDao.isFolderEmpty(fileEntity.parentFolderId)) {
      final parentFolder =
          await _driveDao.getFolderById(fileEntity.parentFolderId);

      transactions.add(await _arweaveDao.prepareFolderEntityTx(
        FolderEntity(
          id: parentFolder.id,
          driveId: fileEntity.driveId,
          parentFolderId: parentFolder.parentFolderId,
          name: parentFolder.name,
        ),
        wallet,
      ));
    }

    final uploadTxs = await _arweaveDao.prepareFileUploadTxs(
      fileEntity,
      event.fileStream,
      wallet,
    );

    transactions.add(uploadTxs.entityTx);
    transactions.add(uploadTxs.dataTx);

    yield FileUploadReady(
      existingFileId,
      fileEntity.name,
      uploadTxs.dataTx.reward,
      fileEntity.size,
      UploadFileToNetwork(
        fileEntity,
        event.filePath,
        transactions,
      ),
    );
  }

  Stream<UploadState> _mapUploadFileToNetworkToState(
      UploadFileToNetwork event) async* {
    final fileEntity = event.fileEntity;

    await _arweaveDao.batchPostTxs(event.uploadTransactions);

    await _driveDao.writeFileEntry(
      fileEntity,
      event.filePath,
    );
  }
}
