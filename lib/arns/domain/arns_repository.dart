import 'dart:convert';

import 'package:ardrive/arns/data/arns_dao.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart' as sdk;
import 'package:ario_sdk/ario_sdk.dart';
import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

abstract class ARNSRepository {
  Future<void> setUndernamesToFile({
    required ARNSUndername undername,
    required String driveId,
    required String fileId,
    required String processId,
  });

  Future<(bool, ARNSUndername?)> nameIsStillAvailableToFile(
      String fileId, String driveId);

  factory ARNSRepository({
    required ArioSDK sdk,
    required ArDriveAuth auth,
    required FileRepository fileRepository,
    required ARNSDao arnsDao,
  }) {
    return _ARNSRepository(
      sdk: sdk,
      auth: auth,
      fileRepository: fileRepository,
      arnsDao: arnsDao,
    );
  }
}

class _ARNSRepository implements ARNSRepository {
  final ArioSDK _sdk;
  final ArDriveAuth _auth;
  final FileRepository _fileRepository;
  final ARNSDao _arnsDao;

  _ARNSRepository({
    required ArioSDK sdk,
    required ArDriveAuth auth,
    required FileRepository fileRepository,
    required ARNSDao arnsDao,
  })  : _sdk = sdk,
        _auth = auth,
        _fileRepository = fileRepository,
        _arnsDao = arnsDao;

  @override
  Future<void> setUndernamesToFile({
    required ARNSUndername undername,
    required String driveId,
    required String fileId,
    required String processId,
  }) async {
    final id = await _sdk.setUndername(
      jwtString: _auth.getJWTAsString(),
      domain: undername.domain,
      txId: undername.record.transactionId,
      undername: undername.name,
    );

    Future.delayed(const Duration(seconds: 2));
    await _sdk.fetchUndernames(_auth.getJWTAsString(),
        sdk.ARNSRecord(domain: undername.domain, processId: processId));

    logger.d('Undername set with id: $id');

    await _arnsDao.saveAntRecord(
      domain: undername.domain,
      transactionId: undername.record.transactionId,
      recordId: id,
      undername: undername.name,
      processId: processId,
    );

    // update file revision with new undernames
    final file = await _fileRepository.getFileEntryById(driveId, fileId);
    final newRevision = file.copyWith(antRegistries: Value(jsonEncode([id])));
    final latestRevision =
        await _fileRepository.getLatestFileRevision(driveId, fileId);
    final fileEntity = newRevision.asEntity()
      ..txId = latestRevision.metadataTxId;
    await _fileRepository.updateFile(newRevision);
    await _fileRepository.updateFileRevision(
        fileEntity, RevisionAction.assignName);
  }

  @override
  Future<(bool, ARNSUndername?)> nameIsStillAvailableToFile(
      String fileId, String driveId) async {
    final file = await _fileRepository.getFileEntryById(driveId, fileId);
    final antRegistries = jsonDecode(file.antRegistries!);
    final undernameId = antRegistries.first;
    logger.d('Undername id: $undernameId');

    final jwt = _auth.getJWTAsString();

    final record =
        await _arnsDao.fetchRecordById(recordId: undernameId).getSingle();

    logger.d('Record: ${record.domain} - ${record.transactionId}');

    final undernames = await _sdk.getUndernames(
      jwt,
      sdk.ARNSRecord(domain: record.domain, processId: record.processId),
    );

    logger.d('Undernames: ${undernames.length}');

    final stillAvailable = undernames.firstWhereOrNull(
      (element) => element.record.transactionId == file.dataTxId,
    );

    logger.d('Still available: $stillAvailable');

    return (stillAvailable != null, stillAvailable);
  }
}
