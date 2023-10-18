import 'dart:async';
import 'dart:convert';
import 'dart:io' show BytesBuilder;

import 'package:ardrive/blocs/constants.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/snapshot_entity.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/pst/pst.dart';
import 'package:ardrive/utils/html/html_util.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/metadata_cache.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/snapshot_item_to_be_created.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:stash_shared_preferences/stash_shared_preferences.dart';
import 'package:uuid/uuid.dart';

part 'create_snapshot_state.dart';

class CreateSnapshotCubit extends Cubit<CreateSnapshotState> {
  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final PstService _pst;
  final TabVisibilitySingleton _tabVisibility;
  @visibleForTesting
  bool throwOnDataComputingForTesting;
  @visibleForTesting
  bool throwOnSignTxForTesting;
  @visibleForTesting
  bool returnWithoutSigningForTesting;

  late DriveID _driveId;
  late String _ownerAddress;
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
    required TabVisibilitySingleton tabVisibility,
    this.throwOnDataComputingForTesting = false,
    this.throwOnSignTxForTesting = false,
    this.returnWithoutSigningForTesting = false,
  })  : _arweave = arweave,
        _profileCubit = profileCubit,
        _driveDao = driveDao,
        _pst = pst,
        _tabVisibility = tabVisibility,
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

    final profileState = _profileCubit.state as ProfileLoggedIn;
    _ownerAddress = profileState.walletAddress;

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

    logger.i(
      'Trusted range to be snapshotted (Current height: $_currentHeight): $_range)',
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
      ownerAddress: _ownerAddress,
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
    logger.i('About to prepare and sign snapshot transaction');

    final isArConnectProfile = await _profileCubit.isCurrentProfileArConnect();

    emit(PreparingAndSigningTransaction(
      isArConnectProfile: isArConnectProfile,
    ));

    await prepareTx(isArConnectProfile);
    await _pst.addCommunityTipToTx(_preparedTx);
    await signTx(isArConnectProfile);

    snapshotEntity.txId = _preparedTx.id;
  }

  @visibleForTesting
  Future<void> prepareTx(bool isArConnectProfile) async {
    final profile = _profileCubit.state as ProfileLoggedIn;
    final wallet = profile.wallet;

    try {
      logger.i(
        'Preparing snapshot transaction with ${isArConnectProfile ? 'ArConnect' : 'JSON wallet'}',
      );

      _preparedTx = await _arweave.prepareEntityTx(
        _snapshotEntity!,
        wallet,
        null,
        // We'll sign it just after adding the tip
        skipSignature: true,
      );
    } catch (e) {
      final isTabFocused = _tabVisibility.isTabFocused();
      if (isArConnectProfile && !isTabFocused) {
        logger.i(
          'Preparing snapshot transaction while user is not focusing the tab. Waiting...',
        );
        await _tabVisibility.onTabGetsFocusedFuture(
          () async => await prepareTx(isArConnectProfile),
        );
      } else {
        logger.e(
          'Error preparing snapshot transaction - isArConnectProfile: $isArConnectProfile, isTabFocused: $isTabFocused',
          e,
        );
        rethrow;
      }
    }
  }

  @visibleForTesting
  Future<void> signTx(bool isArConnectProfile) async {
    final profile = _profileCubit.state as ProfileLoggedIn;
    final wallet = profile.wallet;

    try {
      logger.i(
        'Signing snapshot transaction with ${isArConnectProfile ? 'ArConnect' : 'JSON wallet'}',
      );

      if (throwOnSignTxForTesting) {
        throw Exception('Throwing on purpose for testing');
      } else if (returnWithoutSigningForTesting) {
        return;
      }

      await _preparedTx.sign(wallet);
    } catch (e) {
      final isTabFocused = _tabVisibility.isTabFocused();
      if (isArConnectProfile && !isTabFocused) {
        logger.i(
          'Signing snapshot transaction while user is not focusing the tab. Waiting...',
        );
        await _tabVisibility.onTabGetsFocusedFuture(
          () async {
            await signTx(isArConnectProfile);
          },
        );
      } else {
        logger.e(
          'Error signing snapshot transaction isArConnectProfile: $isArConnectProfile, isTabFocused: $isTabFocused',
          e,
        );
        rethrow;
      }
    }
  }

  Future<Uint8List> _getSnapshotData() async {
    logger.i('Computing snapshot data');

    emit(ComputingSnapshotData(
      driveId: _driveId,
      range: _range,
    ));

    // For testing purposes
    if (throwOnDataComputingForTesting) {
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

    logger.i('Finished computing snapshot data');

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

    final double? usdUploadCost = await ConvertArToUSD(arweave: _arweave)
        .convertForUSD(double.parse(arUploadCost));

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

    final metadataCache = await MetadataCache.fromCacheStore(
      await newSharedPreferencesCacheStore(),
    );

    final Uint8List? cachedMetadata = await metadataCache.get(txId);

    final Uint8List entityJsonData = cachedMetadata ??
        await _arweave.dataFromTxId(
          txId,
          null, // key is null because we don't re-encrypt the snapshot data
        );

    if (cachedMetadata == null) {
      // Write to the cache the data we just fetched
      await metadataCache.put(txId, entityJsonData);
    }

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
      logger.i('Failed to confirm the upload: Wallet mismatch');
      emit(SnapshotUploadFailure());
      return;
    }

    try {
      emit(UploadingSnapshot());

      await _arweave.postTx(_preparedTx);

      emit(SnapshotUploadSuccess());
    } catch (err, stacktrace) {
      logger.e('Error while posting the snapshot transaction', err, stacktrace);
      emit(SnapshotUploadFailure());
    }
  }

  void cancelSnapshotCreation() {
    logger.i('User cancelled the snapshot creation');

    _wasSnapshotDataComputingCanceled = true;
  }
}
