import 'dart:convert';
import 'dart:io' show BytesBuilder;

import 'package:ardrive/blocs/constants.dart';
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

class CreateSnapshotCubit extends Cubit<CreateSnapshotState> {
  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final PstService _pst;
  final bool _forceFailOnDataComputingForTesting;

  late DriveID _driveId;
  late Range _range;
  late int _currentHeight;

  SnapshotItemToBeCreated? _itemToBeCreated;
  SnapshotEntity? _snapshotEntity;

  CreateSnapshotCubit({
    required ArweaveService arweave,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
    required PstService pst,
    @visibleForTesting bool forceFailOnDataComputingForTesting = false,
  })  : _arweave = arweave,
        _profileCubit = profileCubit,
        _driveDao = driveDao,
        _pst = pst,
        _forceFailOnDataComputingForTesting =
            forceFailOnDataComputingForTesting,
        super(CreateSnapshotInitial());

  Future<void> confirmDriveAndHeighRange(
    DriveID driveId, {
    Range? range,
  }) async {
    await _reset(driveId);

    _setTrustedRange(range);

    late Uint8List data;
    try {
      data = await _getSnapshotData();
    } catch (e) {
      emit(ComputeSnapshotDataFailure(errorMessage: e.toString()));
      return;
    }

    _setupSnapshotEntityWithBlob(data);

    final uploadSnapshotItemParams = await _snapshotParametersFromEntityAndData(
      _snapshotEntity!,
      data,
    );
    final tx = uploadSnapshotItemParams.signedTx;

    final costResult = await _computeCostAndCheckBalance(tx);
    if (costResult == null) return;

    await _emitConfirming(costResult, data.length, uploadSnapshotItemParams);
  }

  Future<void> _reset(DriveID driveId) async {
    final currentHeight = await _arweave.getCurrentBlockHeight();
    _currentHeight = currentHeight;
    _driveId = driveId;
    _itemToBeCreated = null;
    _snapshotEntity = null;
  }

  void _setTrustedRange(Range? range) {
    final maximumHeightToSnapshot =
        _currentHeight - kRequiredTxConfirmationCount;

    if (range != null) {
      _range = range.end > maximumHeightToSnapshot
          ? Range(start: range.start, end: maximumHeightToSnapshot)
          : range;
    } else {
      _range = Range(start: 0, end: maximumHeightToSnapshot);
    }

    // ignore: avoid_print
    print(
      'Trusted range to be snapshotted (Current height: $_currentHeight): $_range',
    );
  }

  SnapshotItemToBeCreated get _newItemToBeCreated {
    if (_itemToBeCreated != null) {
      return _itemToBeCreated!;
    }

    // declare the GQL read stream out of arweave
    final gqlEdgesStream = _arweave.getSegmentedTransactionsFromDrive(
      _driveId,
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
      driveId: _driveId,
      subRanges: HeightRange(rangeSegments: [_range]),
      source: gqlNodesStream,
      jsonMetadataOfTxId: _jsonMetadataOfTxId,
    );

    _itemToBeCreated = snapshotItemToBeCreated;

    return snapshotItemToBeCreated;
  }

  Future<CreateSnapshotParameters> _snapshotParametersFromEntityAndData(
    SnapshotEntity snapshotEntity,
    Uint8List data,
  ) async {
    final profile = _profileCubit.state as ProfileLoggedIn;
    final wallet = profile.wallet;

    final preparedTx = await _arweave.prepareEntityTx(
      snapshotEntity,
      wallet,
      null,
      // We'll sign it just after adding the tip
      skipSignature: true,
    );

    await _pst.addCommunityTipToTx(preparedTx);

    await preparedTx.sign(wallet);

    snapshotEntity.txId = preparedTx.id;

    final uploadSnapshotItemParams = CreateSnapshotParameters(
      signedTx: preparedTx,
    );

    return uploadSnapshotItemParams;
  }

  Future<Uint8List> _getSnapshotData() async {
    emit(ComputingSnapshotData(
      driveId: _driveId,
      range: _range,
    ));

    // For testing purposes
    if (_forceFailOnDataComputingForTesting) {
      throw Exception('Fake network error');
    }

    // FIXME: This uses a lot of memory
    // it will be a Uint8List buffer for now
    // ignore: deprecated_export_use
    final dataBuffer = BytesBuilder(copy: false);

    // Stream snapshot data to the temporal buffer
    await for (final item in _newItemToBeCreated.getSnapshotData()) {
      dataBuffer.add(item);
    }

    final data = dataBuffer.takeBytes();
    return data;
  }

  void _setupSnapshotEntityWithBlob(Uint8List data) {
    final dataStart = _newItemToBeCreated.dataStart;
    final dataEnd = _newItemToBeCreated.dataEnd;

    // declares the new snapshot entity
    final snapshotEntity = SnapshotEntity(
      id: const Uuid().v4(),
      driveId: _driveId,
      blockStart: _range.start,
      blockEnd: _range.end,
      dataStart: dataStart,
      dataEnd: dataEnd,
      data: data,
    );

    _snapshotEntity = snapshotEntity;
  }

  Future<BigInt?> _computeCostAndCheckBalance(Transaction tx) async {
    final totalCost = tx.reward + tx.quantity;

    final profile = _profileCubit.state as ProfileLoggedIn;
    final walletBalance = profile.walletBalance;

    if (walletBalance < totalCost) {
      emit(CreateSnapshotInsufficientBalance(
        walletBalance: walletBalance.toString(),
        arCost: winstonToAr(totalCost),
      ));
      return null;
    }

    return totalCost;
  }

  Future<void> _emitConfirming(
    BigInt totalCost,
    int dataSize,
    CreateSnapshotParameters params,
  ) async {
    final arUploadCost = winstonToAr(totalCost);
    final usdUploadCost = await _arweave
        .getArUsdConversionRate()
        .then((conversionRate) => double.parse(arUploadCost) * conversionRate);

    emit(ConfirmingSnapshotCreation(
      snapshotSize: dataSize,
      arUploadCost: arUploadCost,
      usdUploadCost: usdUploadCost,
      createSnapshotParams: params,
    ));
  }

  Future<Uint8List> _jsonMetadataOfTxId(String txId) async {
    final drive =
        await _driveDao.driveById(driveId: _driveId).getSingleOrNull();
    final isPrivate = drive != null && drive.privacy != DrivePrivacy.public;

    // gather from arweave if not cached
    final Uint8List entityJsonData = await _arweave.dataFromTxId(
      txId,
      null, // key is null because we don't re-encrypt the snapshot data
    );

    if (isPrivate) {
      final safeEntityDataFromArweave = Uint8List.fromList(
        utf8.encode(base64Encode(entityJsonData)),
      );

      return safeEntityDataFromArweave;
    }

    return entityJsonData;
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

  CreateSnapshotParameters({
    required this.signedTx,
  });
}
