import 'dart:async';
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
import 'package:ardrive/utils/html/html_util.dart';
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
  late Transaction _preparedTx;

  bool _wasSnapshotDataComputingCanceled = false;

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
    try {
      await _reset(driveId);
    } catch (e) {
      emit(ComputeSnapshotDataFailure(errorMessage: e.toString()));
      return;
    }

    _setTrustedRange(range);

    late Uint8List data;
    try {
      data = await _getSnapshotData();

      if (_wasCancelled()) return;
    } catch (e) {
      if (_wasCancelled()) return;

      // If it was not cancelled, then there was a failure.
      emit(ComputeSnapshotDataFailure(errorMessage: e.toString()));
      return;
    }

    _setupSnapshotEntityWithBlob(data);

    await _prepareAndSignTx(
      _snapshotEntity!,
      data,
    );

    final costResult = await _computeCostAndCheckBalance();
    if (costResult == null) return;

    await _emitConfirming(costResult, data.length);
  }

  bool _wasCancelled() {
    if (_wasSnapshotDataComputingCanceled) {
      _wasSnapshotDataComputingCanceled = false;

      return true;
    }

    return false;
  }

  Future<void> _reset(DriveID driveId) async {
    _currentHeight = await _arweave.getCurrentBlockHeight();
    _driveId = driveId;
    _itemToBeCreated = null;
    _snapshotEntity = null;
    _wasSnapshotDataComputingCanceled = false;
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

  Future<void> _prepareAndSignTx(
    SnapshotEntity snapshotEntity,
    Uint8List data,
  ) async {
    // ignore: avoid_print
    print('About to prepare and sign snapshot transaction');

    final isArConnectProfile = await _profileCubit.isCurrentProfileArConnect();
    emit(PreparingAndSigningTransaction(
      isArConnectProfile: isArConnectProfile,
    ));

    await _prepareTx(isArConnectProfile);
    await _pst.addCommunityTipToTx(_preparedTx);
    await _signTx(isArConnectProfile);

    snapshotEntity.txId = _preparedTx.id;
  }

  Future<void> _prepareTx(bool isArConnectProfile) async {
    final profile = _profileCubit.state as ProfileLoggedIn;
    final wallet = profile.wallet;

    if (isArConnectProfile) {
      try {
        await closeVisibilityChangeStream();
      } catch (_) {
        // The stream was not yet open. Nothing to do
      }
    }

    try {
      // ignore: avoid_print
      print(
        'Preparing snapshot transaction with ${isArConnectProfile ? 'ArConnect' : 'JSON wallet'}',
      );
      _preparedTx = await _arweave.prepareEntityTx(
        _snapshotEntity!,
        wallet,
        null,
        // We'll sign it just after adding the tip
        skipSignature: true,
      );
    } catch (_) {
      if (isArConnectProfile && isBrowserTabHidden()) {
        // ignore: avoid_print
        print(
          'Preparing snapshot transaction while user is not focusing the tab. Waiting...',
        );
        await whenBrowserTabIsUnhiddenFuture(
          _prepareTx,
        );
      } else {
        rethrow;
      }
    }
  }

  Future<void> _signTx(bool isArConnectProfile) async {
    final profile = _profileCubit.state as ProfileLoggedIn;
    final wallet = profile.wallet;

    if (isArConnectProfile) {
      try {
        await closeVisibilityChangeStream();
      } catch (_) {
        // The stream was not yet open. Nothing to do
      }
    }

    try {
      // ignore: avoid_print
      print(
        'Signing snapshot transaction with ${isArConnectProfile ? 'ArConnect' : 'JSON wallet'}',
      );
      await _preparedTx.sign(wallet);
    } catch (e) {
      if (isArConnectProfile && isBrowserTabHidden()) {
        // ignore: avoid_print
        print(
          'Signing snapshot transaction while user is not focusing the tab. Waiting...',
        );
        await whenBrowserTabIsUnhiddenFuture(_signTx);
      } else {
        rethrow;
      }
    }
  }

  Future<Uint8List> _getSnapshotData() async {
    // ignore: avoid_print
    print('Computing snapshot data');

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

    await for (final chunk in _newItemToBeCreated.getSnapshotData()) {
      if (_wasSnapshotDataComputingCanceled) {
        emit(CreateSnapshotInitial());

        throw Exception('Snapshot data stream subscription was canceled');
      }

      dataBuffer.add(chunk);
    }

    // ignore: avoid_print
    print('Finished computing snapshot data');

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

  Future<BigInt?> _computeCostAndCheckBalance() async {
    final totalCost = _preparedTx.reward + _preparedTx.quantity;

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
  ) async {
    final arUploadCost = winstonToAr(totalCost);
    final usdUploadCost = await _arweave
        .getArUsdConversionRate()
        .then((conversionRate) => double.parse(arUploadCost) * conversionRate);

    emit(ConfirmingSnapshotCreation(
      snapshotSize: dataSize,
      arUploadCost: arUploadCost,
      usdUploadCost: usdUploadCost,
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
      emit(UploadingSnapshot());

      await _arweave.postTx(_preparedTx);

      emit(SnapshotUploadSuccess());
    } catch (err) {
      // ignore: avoid_print
      print(
          'Error while posting the snapshot transaction: ${(err as TypeError).stackTrace}');
      emit(SnapshotUploadFailure(errorMessage: '$err'));
    }
  }

  void cancelSnapshotCreation() {
    // ignore: avoid_print
    print('User cancelled the snapshot creation');

    _wasSnapshotDataComputingCanceled = true;
  }
}
