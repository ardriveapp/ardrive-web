import 'dart:convert';
import 'dart:io' show BytesBuilder;

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/snapshot_entity.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/pst/pst.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/snapshot_item_to_be_created.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

part 'create_snapshot_state.dart';

const kRequiredTxConfirmationCount = 15;

class CreateSnapshotCubit extends Cubit<CreateSnapshotState> {
  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final PstService _pst;

  late DriveID _driveId;
  late Range _range;
  late int _currentHeight;

  CreateSnapshotCubit({
    required ArweaveService arweave,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
    required PstService pst,
  })  : _arweave = arweave,
        _profileCubit = profileCubit,
        _driveDao = driveDao,
        _pst = pst,
        super(CreateSnapshotInitial());

  Future<void> selectDriveAndHeightRange(
    DriveID driveId, {
    Range? range,
  }) async {
    print('Select drive $driveId and height range $range');

    final currentHeight = await _arweave.getCurrentBlockHeight();

    final maximumHeightToSnapshot =
        currentHeight - kRequiredTxConfirmationCount;

    _driveId = driveId;

    if (range != null) {
      _range = range.end > maximumHeightToSnapshot
          ? Range(start: range.start, end: maximumHeightToSnapshot)
          : range;
    } else {
      _range = Range(start: 0, end: maximumHeightToSnapshot);
    }

    print(
      'Trusted range to be snapshotted (Current height: $currentHeight): $_range',
    );

    _currentHeight = currentHeight;

    if (!_isValidHeightRange()) {
      final errMessage =
          'Invalid height range chosen. ${_range.end} >= $_currentHeight';
      print(errMessage);
      emit(ComputeSnapshotDataFailure(
        errorMessage: errMessage,
      ));
      return;
    }

    // FIXME: This uses a lot of memory
    // it will be a Uint8List buffer for now
    // ignore: deprecated_export_use
    final dataBuffer = BytesBuilder(copy: false);

    emit(ComputingSnapshotData(
      driveId: driveId,
      range: _range,
    ));

    print('Computing snapshot data event emmited');

    // declare the GQL read stream out of arweave
    final gqlEdgesStream = _arweave.getSegmentedTransactionsFromDrive(
      driveId,
      minBlockHeight: _range.start,
      maxBlockHeight: _range.end,
    );

    // transforms the stream of arrays into a flat stream
    final flatGQLEdgesStream = gqlEdgesStream.expand((element) => element);

    // maps the items to GQL Nodes
    final gqlNodesStream = flatGQLEdgesStream.map((edge) => edge.node);

    // declares the reading stream from the SnapshotItemToBeCreated
    final snapshotItemToBeCreated = SnapshotItemToBeCreated(
      blockStart: _range.start,
      blockEnd: _range.end,
      driveId: driveId,
      subRanges: HeightRange(rangeSegments: [_range]),
      source: gqlNodesStream,
      jsonMetadataOfTxId: _jsonMetadataOfTxId,
    );

    print('About to start reading the snapshot data stream');

    // Stream snapshot data to the temporal file
    await for (final item in snapshotItemToBeCreated.getSnapshotData()) {
      print('##> $item');
      dataBuffer.add(item);
    }

    print('Done reading the snapshot data stream');

    final dataStart = snapshotItemToBeCreated.dataStart;
    final dataEnd = snapshotItemToBeCreated.dataEnd;

    print('Data start: $dataStart');
    print('Data end: $dataEnd');

    final data = dataBuffer.takeBytes();

    // declares the new snapshot entity
    final snapshotEntity = SnapshotEntity(
      id: const Uuid().v4(),
      driveId: driveId,
      blockStart: _range.start,
      blockEnd: _range.end,
      dataStart: dataStart,
      dataEnd: dataEnd,
      data: data,
    );

    print('Snapshot entity created: $snapshotEntity');

    final profile = _profileCubit.state as ProfileLoggedIn;
    final wallet = profile.wallet;
    final preparedTx = await _arweave.prepareEntityTx(
      snapshotEntity,
      wallet,
      // key is null because we don't re-encrypt the snapshot data
    );

    await _pst.addCommunityTipToTx(preparedTx);

    // Sign again because the tip does change the signature
    await preparedTx.sign(wallet);

    snapshotEntity.txId = preparedTx.id;

    final uploadSnapshotItemParams = CreateSnapshotParameters(
      signedTx: preparedTx,
      addSnapshotItemToDatabase: () =>
          _driveDao.insertSnapshotEntry(snapshotEntity),
    );

    final totalCost = preparedTx.reward + preparedTx.quantity;

    if (profile.walletBalance < totalCost) {
      emit(
        ComputeSnapshotDataFailure(
          errorMessage: '''Insufficient AR balance to create snapshot.
Balance: ${profile.walletBalance} AR, Cost: $totalCost AR''',
        ),
      );
      return;
    }

    final arUploadCost = winstonToAr(totalCost);
    final usdUploadCost = await _arweave
        .getArUsdConversionRate()
        .then((conversionRate) => double.parse(arUploadCost) * conversionRate);

    emit(ConfirmingSnapshotCreation(
      snapshotSize: data.length,
      arUploadCost: arUploadCost,
      usdUploadCost: usdUploadCost,
      createSnapshotParams: uploadSnapshotItemParams,
    ));
  }

  bool _isValidHeightRange() {
    return _range.end <= _currentHeight;
  }

  Future<String> _jsonMetadataOfTxId(String txId) async {
    print('About to request metadata of $txId');

    // check if the entity is already in the DB
    final Entity? entity =
        await _driveDao.getEntityByMetadataTxId(_driveId, txId);
    if (entity != null) {
      final String entityAsString = jsonEncode(entity);

      print('Cache hit! - $txId');

      // Now that we can gather the data drom the cache, we must re-encrypt it
      // TODO: encrypt if private!
      final drive =
          await _driveDao.driveById(driveId: _driveId).getSingleOrNull();
      if (drive != null && drive.privacy == DrivePrivacy.public) {
        return entityAsString;
      }
    }

    print('Cache miss! - $txId');

    // gather from arweave if not cached
    final String entityAsString = await _arweave.entityMetadataFromFromTxId(
      txId,
      null, // key is null because we don't re-encrypt the snapshot data
    );

    print('Requested to arweave - $txId');
    return entityAsString;
  }

  Future<void> confirmSnapshotCreation() async {
    if (await _profileCubit.logoutIfWalletMismatch()) {
      // ignore: avoid_print
      print('Failed to confirm the upload: Wallet mismatch');
      emit(SnapshotUploadFailure(errorMessage: 'Wallet mismatch.'));
      return;
    }

    try {
      final params = (state as ConfirmingSnapshotCreation).createSnapshotParams;

      emit(UploadingSnapshot());

      await _arweave.postTx(params.signedTx);
      await params.addSnapshotItemToDatabase();

      emit(SnapshotUploadSuccess());
    } catch (err) {
      // ignore: avoid_print
      print(
          'Error while posting the snapshot transaction: ${(err as TypeError).stackTrace}');
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
