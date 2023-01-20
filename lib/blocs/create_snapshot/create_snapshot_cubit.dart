import 'dart:convert';

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/snapshot_entity.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/snapshot_item_to_be_created.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

part 'create_snapshot_state.dart';

class CreateSnapshotCubit extends Cubit<CreateSnapshotState> {
  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;

  late DriveID _driveId;
  late Range _range;
  late int _currentHeight;

  CreateSnapshotCubit({
    required ArweaveService arweave,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
  })  : _arweave = arweave,
        _profileCubit = profileCubit,
        _driveDao = driveDao,
        super(CreateSnapshotInitial());

  Future<void> selectDriveAndHeightRange(
    DriveID driveId,
    Range range,
    int currentHeight,
  ) async {
    _driveId = driveId;
    _range = range;
    _currentHeight = currentHeight;

    if (_isValidHeightRange()) {
      emit(ComputeSnapshotDataFailure(
        errorMessage: 'Invalid height range chosen',
      ));
    }

    // FIXME: This uses a lot of memory
    // it will be a Uint8List buffer for now
    final dataBuffer = Uint8List(0);

    emit(ComputingSnapshotData(
      driveId: driveId,
      range: range,
    ));

    // declare the GQL read stream out of arweave
    final gqlEdgesStream = _arweave.getSegmentedTransactionsFromDrive(
      driveId,
      minBlockHeight: range.start,
      maxBlockHeight: range.end,
    );

    // transforms the stream of arrays into a flat stream
    final flatGQLEdgesStream = gqlEdgesStream.expand((element) => element);

    // maps the items to GQL Nodes
    final gqlNodesStream = flatGQLEdgesStream.map((edge) => edge.node);

    // declares the reading stream from the SnapshotItemToBeCreated
    final snapshotItemToBeCreated = SnapshotItemToBeCreated(
      blockStart: range.start,
      blockEnd: range.end,
      driveId: driveId,
      subRanges: HeightRange(rangeSegments: [range]),
      source: gqlNodesStream,
      jsonMetadataOfTxId: _jsonMetadataOfTxId,
    );

    // Stream snapshot data to the temporal file
    await for (final item in snapshotItemToBeCreated.getSnapshotData()) {
      dataBuffer.addAll(item);
    }

    final dataStart = snapshotItemToBeCreated.dataStart;
    final dataEnd = snapshotItemToBeCreated.dataEnd;

    // declares the new snapshot entity
    final snapshotEntity = SnapshotEntity(
      id: const Uuid().v4(),
      driveId: driveId,
      blockStart: range.start,
      blockEnd: range.end,
      dataStart: dataStart,
      dataEnd: dataEnd,
      data: dataBuffer,
    );

    final profile = _profileCubit.state as ProfileLoggedIn;
    final wallet = profile.wallet;
    final preparedTx = await _arweave.prepareEntityTx(
      snapshotEntity,
      wallet,
      // key is null because we don't re-encrypt the snapshot data
    );

    snapshotEntity.txId = preparedTx.id;

    final uploadSnapshotItemParams = CreateSnapshotParameters(
      signedTx: preparedTx,
      addSnapshotItemToDatabase: () => _driveDao.transaction(() async {
        await _driveDao.writeSnapshotEntity(snapshotEntity);
      }),
    );

    // TODO: estimate upload cost
    const arUploadCost = '0';
    const usdUploadCost = 0.0;

    // TODO: emit ConfirmUpload or ComputeSnapshotDataFailure
    emit(ConfirmingSnapshotCreation(
      snapshotSize: dataBuffer.length,
      arUploadCost: arUploadCost,
      usdUploadCost: usdUploadCost,
      createSnapshotParams: uploadSnapshotItemParams,
    ));
  }

  bool _isValidHeightRange() {
    return _range.end <= _currentHeight;
  }

  Future<String> _jsonMetadataOfTxId(String txId) async {
    // check if the entity is already in the DB
    final Entity? entity = await _driveDao.getEntityByMetadataTxId(txId);
    if (entity == null) {
      final String entityAsString = jsonEncode(entity);
      return entityAsString;
    }

    // gather from arweave if not cached
    final driveKey = await _driveDao.getDriveKeyFromMemory(_driveId);
    final String entityAsString =
        await _arweave.entityMetadataFromFromTxId(txId, driveKey);
    return entityAsString;
  }

  void confirmSnapshotCreation() async {
    // if (await _profileCubit.logoutIfWalletMismatch()) {
    //   emit(CreateManifestWalletMismatch());
    //   return;
    // }

    try {
      final params = (state as ConfirmingSnapshotCreation).createSnapshotParams;

      emit(UploadingSnapshot());

      await _arweave.client.transactions.post(params.signedTx);
      await params.addSnapshotItemToDatabase();

      emit(SnapshotUploadSuccess());
    } catch (err) {
      // ignore: avoid_print
      print('Error while posting the snapshot transaction: $err');
      emit(SnapshotUploadFailure(errorMessage: '$err'));
    }
  }
}

class CreateSnapshotParameters {
  final Transaction signedTx;
  final Future<void> Function() addSnapshotItemToDatabase;

  CreateSnapshotParameters({
    required this.signedTx,
    required this.addSnapshotItemToDatabase,
  });
}
