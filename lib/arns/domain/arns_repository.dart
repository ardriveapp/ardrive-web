import 'dart:async';
import 'dart:convert';

import 'package:ardrive/arns/data/arns_dao.dart';
import 'package:ardrive/arns/domain/exceptions.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart' as sdk;
import 'package:ario_sdk/ario_sdk.dart';
import 'package:drift/drift.dart';

abstract class ARNSRepository {
  Future<void> setUndernamesToFile({
    required ARNSUndername undername,
    required String driveId,
    required String fileId,
    required String processId,
    bool uploadNewRevision = true,
  });
  Future<void> createUndername({required ARNSUndername undername});
  Future<List<sdk.ANTRecord>> getAntRecordsForWallet(String address,
      {bool update = false});
  Future<List<sdk.ARNSUndername>> getARNSUndernames(sdk.ANTRecord record,
      {bool update = false});
  Future<void> updateARNSRecordsActiveStatus({
    required String domain,
    required String name,
  });
  Future<void> saveAllFilesWithAssignedNames();
  Future<List<ArnsRecord>> getActiveARNSRecordsForFile(String fileId);
  Future<void> waitForARNSRecordsToUpdate();
  Future<sdk.ARNSUndername> getUndernameByDomainAndName(
      String domain, String name);
  Future<List<sdk.ArNSNameModel>> getARNSNameModelsForWallet(String address);
  Future<PrimaryNameDetails> getPrimaryName(String address,
      {bool update = false, bool getLogo = true});

  factory ARNSRepository({
    required ArioSDK sdk,
    required ArDriveAuth auth,
    required FileRepository fileRepository,
    required ARNSDao arnsDao,
    required DriveDao driveDao,
    required TurboUploadService turboUploadService,
    required ArweaveService arweave,
  }) {
    return _ARNSRepository(
      sdk: sdk,
      auth: auth,
      fileRepository: fileRepository,
      arnsDao: arnsDao,
      driveDao: driveDao,
      turboUploadService: turboUploadService,
      arweave: arweave,
    );
  }
}

class _ARNSRepository implements ARNSRepository {
  final ArioSDK _sdk;
  final ArDriveAuth _auth;
  final FileRepository _fileRepository;
  final ARNSDao _arnsDao;
  final DriveDao _driveDao;
  final TurboUploadService _turboUploadService;
  final ArweaveService _arweave;

  _ARNSRepository({
    required ArioSDK sdk,
    required ArDriveAuth auth,
    required FileRepository fileRepository,
    required ARNSDao arnsDao,
    required DriveDao driveDao,
    required TurboUploadService turboUploadService,
    required ArweaveService arweave,
  })  : _sdk = sdk,
        _auth = auth,
        _fileRepository = fileRepository,
        _driveDao = driveDao,
        _turboUploadService = turboUploadService,
        _arweave = arweave,
        _arnsDao = arnsDao,
        super() {
    auth.onAuthStateChanged().listen((user) {
      if (user == null) {
        _cachedUndernames.clear();
        _cachedPrimaryName = null;
      }
    });
  }

  final Map<String, Map<String, ARNSUndername>> _cachedUndernames = {};
  PrimaryNameDetails? _cachedPrimaryName;

  @override
  Future<void> setUndernamesToFile({
    required ARNSUndername undername,
    required String driveId,
    required String fileId,
    required String processId,
    bool uploadNewRevision = true,
  }) async {
    if (_auth.currentUser.profileType == ProfileType.arConnect) {
      logger.d('Setting undername with ArConnect');

      final id = await _sdk.setUndernameWithArConnect(
        txId: undername.record.transactionId,
        domain: undername.domain,
        undername: undername.name,
      );

      logger.d('Undername set with ArConnect: $id');
    } else {
      await _sdk.setUndername(
        jwtString: _auth.getJWTAsString(),
        domain: undername.domain,
        txId: undername.record.transactionId,
        undername: undername.name,
      );
    }

    _cachedUndernames[undername.domain]![undername.name] = undername;

    await _arnsDao.saveARNSRecord(
      domain: undername.domain,
      transactionId: undername.record.transactionId,
      isActive: true,
      undername: undername.name,
      ttl: undername.record.ttlSeconds,
      fileId: fileId,
    );

    await updateARNSRecordsActiveStatus(
      domain: undername.domain,
      name: undername.name,
    );

    if (!uploadNewRevision) {
      return;
    }

    // update file revision with new undernames
    final file = await _fileRepository.getFileEntryById(driveId, fileId);

    /// current names
    List<String> currentNames;

    if (file.assignedNames != null) {
      currentNames =
          (jsonDecode(file.assignedNames!)['assignedNames'] as List<dynamic>)
              .map((e) => e.toString())
              .toList();
    } else {
      currentNames = [];
    }

    final assignedNames = {
      'assignedNames': [...currentNames, getLiteralARNSRecordName(undername)]
    };

    final fileWithNames = file.copyWith(
      assignedNames: Value(jsonEncode(assignedNames)),
    );

    final fileEntity = fileWithNames.asEntity();

    if (_turboUploadService.useTurboUpload) {
      final dataItem = await _arweave.prepareEntityDataItem(
        fileEntity,
        _auth.currentUser.wallet,
      );

      await _turboUploadService.postDataItem(
        dataItem: dataItem,
        wallet: _auth.currentUser.wallet,
      );

      fileEntity.txId = dataItem.id;

      await _fileRepository.updateFile(fileWithNames);
      await _fileRepository.updateFileRevision(
          fileEntity, RevisionAction.assignName);
    }
  }

  @override
  Future<void> createUndername({
    required ARNSUndername undername,
  }) async {
    // verify if the undername already exists
    final undernames = _cachedUndernames[undername.domain]!;

    if (undernames.containsKey(undername.name)) {
      throw UndernameAlreadyExistsException();
    }

    if (_auth.currentUser.profileType == ProfileType.arConnect) {
      logger.d('Setting undername with ArConnect');

      final id = await _sdk.setUndernameWithArConnect(
        txId: undername.record.transactionId,
        domain: undername.domain,
        undername: undername.name,
      );

      logger.d('Undername set with ArConnect: $id');
    } else {
      await _sdk.setUndername(
        jwtString: _auth.getJWTAsString(),
        domain: undername.domain,
        txId: undername.record.transactionId,
        undername: undername.name,
      );
    }

    _cachedUndernames[undername.domain]![undername.name] = undername;

    await _arnsDao.saveARNSRecord(
      domain: undername.domain,
      transactionId: undername.record.transactionId,
      isActive: true,
      undername: undername.name,
      ttl: undername.record.ttlSeconds,
      fileId: '', // we don't have a file id for the undername
    );

    await updateARNSRecordsActiveStatus(
      domain: undername.domain,
      name: undername.name,
    );
  }

  Completer<List<sdk.ANTRecord>>? _getARNSUndernamesCompleter;

  @override
  Future<List<sdk.ANTRecord>> getAntRecordsForWallet(
    String address, {
    bool update = false,
  }) async {
    if (!update &&
        lastUpdated != null &&
        lastUpdated!
            .isAfter(DateTime.now().subtract(const Duration(minutes: 15)))) {
      final allRecords = await _arnsDao.getAllANTRecords().get();

      return allRecords
          .map((e) => sdk.ANTRecord(domain: e.domain, processId: e.processId))
          .toList();
    }

    if (_getARNSUndernamesCompleter != null) {
      return _getARNSUndernamesCompleter!.future;
    }
    logger.d('Loading names');
    final date = DateTime.now();

    _getARNSUndernamesCompleter = Completer();

    try {
      final processes = await _sdk.getAntRecordsForWallet(address);

      final records = <sdk.ANTRecord>[];

      for (var process in processes) {
        final record = ANTRecord(
          domain: process.names.keys.first,
          processId: process.names.values.first.processId,
        );

        records.add(record);

        // saves the undernames to the cache
        final undernames = process.state.records.keys.map((e) {
          final record = process.state.records[e];

          return ARNSUndername(
            record: ARNSRecord(
              transactionId: record!.transactionId,
              ttlSeconds: record.ttlSeconds,
            ),
            name: e,
            domain: process.names.keys.first,
          );
        }).toList();

        final undernamesMap = <String, ARNSUndername>{};

        for (var undername in undernames) {
          undernamesMap[undername.name] = undername;
        }

        _cachedUndernames[record.domain] = undernamesMap;
      }

      await _arnsDao.saveAntRecords(records.map(toAntRecordFromSDK).toList());

      lastUpdated = DateTime.now();

      logger.d(
          'Names loaded in ${DateTime.now().difference(date).inMilliseconds}ms');

      _getARNSUndernamesCompleter!.complete(records);

      _getARNSUndernamesCompleter = null;
      return records;
    } catch (e) {
      logger.e('Error getting ANT records for wallet: $e');

      _getARNSUndernamesCompleter!.completeError(e);

      _getARNSUndernamesCompleter = null;

      return [];
    }
  }

  @override
  Future<List<sdk.ARNSUndername>> getARNSUndernames(
    sdk.ANTRecord record, {
    bool update = false,
  }) async {
    if (!update &&
        _cachedUndernames.containsKey(record.domain) &&
        _cachedUndernames[record.domain]!.isNotEmpty) {
      return _cachedUndernames[record.domain]!.values.toList();
    }

    final undernames = await _sdk.getUndernames(
      _auth.getJWTAsString(),
      record,
    );

    final undernamesMap = <String, ARNSUndername>{};

    for (var undername in undernames) {
      undernamesMap[undername.name] = undername;
    }

    _cachedUndernames[record.domain] = undernamesMap;

    return undernames;
  }

  DateTime? lastUpdated;

  @override
  Future<void> updateARNSRecordsActiveStatus({
    required String domain,
    required String name,
  }) async {
    final cachedRecord = _cachedUndernames[domain]![name];

    final records =
        await _arnsDao.getARNSRecordByName(domain: domain, name: name).get();

    for (final record in records) {
      await _arnsDao.updateARNSRecordActiveStatus(
        id: record.id,
        isActive: record.transactionId == cachedRecord!.record.transactionId,
      );
    }
  }

  @override
  Future<List<ArnsRecord>> getActiveARNSRecordsForFile(String fileId) async {
    return await _arnsDao.getActiveARNSRecordsForFileId(fileId: fileId).get();
  }

  @override
  Future<void> saveAllFilesWithAssignedNames() async {
    final files = await _driveDao.getFilesWithAssignedNames().get();
    for (final file in files) {
      final assignedNames =
          jsonDecode(file.assignedNames!)['assignedNames'] as List<dynamic>;
      for (final undername in assignedNames) {
        final nameAndDomain = extractNameAndDomain(undername);
        final domain = nameAndDomain['domain']!;
        final name = nameAndDomain['name'] ?? '@';
        if (_cachedUndernames[domain] == null) {
          continue;
        }

        final cachedUndername = _cachedUndernames[domain]![name];

        if (cachedUndername == null) {
          continue;
        }

        final existentRecordResult = await _arnsDao
            .getARNSRecordByNameAndFileId(
                domain: domain, name: name, fileId: file.id)
            .get();

        if (existentRecordResult.isNotEmpty) {
          final existentRecord = existentRecordResult.first;
          await updateARNSRecordsActiveStatus(
            domain: existentRecord.domain,
            name: existentRecord.name,
          );

          continue;
        }

        await _arnsDao.saveARNSRecord(
          domain: domain,
          transactionId: file.dataTxId,
          fileId: file.id,
          isActive: file.dataTxId == cachedUndername.record.transactionId,
          undername: name,
          ttl: cachedUndername.record.ttlSeconds,
        );
      }
    }
  }

  @override
  Future<void> waitForARNSRecordsToUpdate() async {
    if (_getARNSUndernamesCompleter == null) {
      return;
    }

    await _getARNSUndernamesCompleter!.future;
  }

  @override
  Future<sdk.ARNSUndername> getUndernameByDomainAndName(
      String domain, String name) async {
    if (_cachedUndernames.isEmpty) {
      await waitForARNSRecordsToUpdate();
    }

    if (_cachedUndernames[domain] == null) {
      throw Exception('Domain not cached');
    }

    final undername = _cachedUndernames[domain]![name];

    if (undername == null) {
      throw Exception('Undername not cached');
    }

    return undername;
  }

  @override
  Future<List<sdk.ArNSNameModel>> getARNSNameModelsForWallet(
      String address) async {
    return _sdk.getArNSNames(address);
  }

  @override
  Future<PrimaryNameDetails> getPrimaryName(String address,
      {bool update = false, bool getLogo = true}) async {
    logger.d('Getting primary name for address: $address');

    if (!update && _cachedPrimaryName != null) {
      return _cachedPrimaryName!;
    }

    final primaryName = await _sdk.getPrimaryNameDetails(address, getLogo);

    logger.d('Primary name: $primaryName');

    _cachedPrimaryName = primaryName;

    return primaryName;
  }
}

AntRecord toAntRecordFromSDK(sdk.ANTRecord record) {
  return AntRecord(
    domain: record.domain,
    processId: record.processId,
  );
}
