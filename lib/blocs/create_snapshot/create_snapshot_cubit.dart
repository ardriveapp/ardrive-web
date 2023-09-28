import 'dart:async';
import 'dart:convert';
import 'dart:io' show BytesBuilder;

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/constants.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/snapshot_entity.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/services/pst/pst.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/html/html_util.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/metadata_cache.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/snapshot_item_to_be_created.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:stash_shared_preferences/stash_shared_preferences.dart';
import 'package:uuid/uuid.dart';

part 'create_snapshot_state.dart';

class CreateSnapshotCubit extends Cubit<CreateSnapshotState> {
  final ArweaveService _arweave;
  final PaymentService _paymentService;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final PstService _pst;
  final TabVisibilitySingleton _tabVisibility;
  final TurboBalanceRetriever turboBalanceRetriever;
  final ArDriveAuth auth;
  final AppConfig appConfig;
  final TurboUploadService turboService;
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
  Uint8List? data;
  DataItem? _preparedDataItem;
  Transaction? _preparedTx;

  UploadMethod _uploadMethod = UploadMethod.ar;
  UploadCostEstimate _costEstimateAr = UploadCostEstimate.zero();
  UploadCostEstimate _costEstimateTurbo = UploadCostEstimate.zero();
  bool _hasNoTurboBalance = false;
  String _arBalance = '';
  String _turboCredits = '';
  BigInt _turboBalance = BigInt.zero;
  bool _isButtonToUploadEnabled = false;
  bool _isTurboUploadPossible = true;
  bool _sufficentCreditsBalance = false;
  bool _sufficientArBalance = false;
  bool _isFreeThanksToTurbo = false;

  bool get _useTurboUpload =>
      _uploadMethod == UploadMethod.turbo || _isFreeThanksToTurbo;

  bool _wasSnapshotDataComputingCanceled = false;

  SnapshotItemToBeCreated? _itemToBeCreated;
  SnapshotEntity? _snapshotEntity;

  CreateSnapshotCubit({
    required ArweaveService arweave,
    required PaymentService paymentService,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
    required PstService pst,
    required TabVisibilitySingleton tabVisibility,
    required this.turboBalanceRetriever,
    required this.auth,
    required this.appConfig,
    required this.turboService,
    this.throwOnDataComputingForTesting = false,
    this.throwOnSignTxForTesting = false,
    this.returnWithoutSigningForTesting = false,
  })  : _arweave = arweave,
        _paymentService = paymentService,
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

    await _computeCost();
    await _computeBalanceEstimate();
    _computeIsSufficientBalance();
    _computeIsTurboEnabled();
    _computeIsFreeThanksToTurbo();
    _computeIsButtonEnabled();

    await _emitConfirming(
      dataSize: data.length,
    );
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
  ) async {
    logger.i('About to prepare and sign snapshot transaction');

    final isArConnectProfile = await _profileCubit.isCurrentProfileArConnect();

    emit(PreparingAndSigningTransaction(
      isArConnectProfile: isArConnectProfile,
    ));

    await prepareTx(isArConnectProfile);
    await signTx(isArConnectProfile);

    if (_useTurboUpload) {
      snapshotEntity.txId = _preparedDataItem!.id;
    } else {
      snapshotEntity.txId = _preparedTx!.id;
    }
  }

  @visibleForTesting
  Future<void> prepareTx(bool isArConnectProfile) async {
    final profile = _profileCubit.state as ProfileLoggedIn;
    final wallet = profile.wallet;

    try {
      logger.i(
        'Preparing snapshot transaction with ${isArConnectProfile ? 'ArConnect' : 'JSON wallet'}',
      );

      if (_useTurboUpload) {
        _preparedDataItem = await _arweave.prepareEntityDataItem(
          _snapshotEntity!,
          wallet,
          // We'll sign it just after adding the tip
          skipSignature: true,
        );
      } else {
        _preparedTx = await _arweave.prepareEntityTx(
          _snapshotEntity!,
          wallet,
          null,
          // We'll sign it just after adding the tip
          skipSignature: true,
        );
      }
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

      if (_useTurboUpload) {
        await _preparedDataItem!.sign(wallet);
      } else {
        await _preparedTx!.sign(wallet);
      }
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

  Future<void> _computeCost() async {
    final profileState = _profileCubit.state as ProfileLoggedIn;
    final wallet = profileState.wallet;

    UploadCostEstimateCalculatorForAR costCalculatorForAr =
        UploadCostEstimateCalculatorForAR(
      arweaveService: _arweave,
      pstService: _pst,
      arCostToUsd: ConvertArToUSD(arweave: _arweave),
    );

    final turboCostCalc = TurboCostCalculator(paymentService: _paymentService);
    TurboUploadCostCalculator costCalculatorForTurbo =
        TurboUploadCostCalculator(
      turboCostCalculator: turboCostCalc,
      priceEstimator: TurboPriceEstimator(
        wallet: wallet,
        paymentService: _paymentService,
        costCalculator: turboCostCalc,
      ),
    );

    _costEstimateAr = await costCalculatorForAr.calculateCost(
      totalSize: _snapshotEntity!.data!.length,
    );
    _costEstimateTurbo = await costCalculatorForTurbo.calculateCost(
      totalSize: _snapshotEntity!.data!.length,
    );
  }

  Future<void> refreshTurboBalance() async {
    final profileState = _profileCubit.state as ProfileLoggedIn;
    final wallet = profileState.wallet;

    final turboBalance =
        await turboBalanceRetriever.getBalance(wallet).catchError((e) {
      logger.e('Error while retrieving turbo balance', e);
      return BigInt.zero;
    });

    _turboBalance = turboBalance;
    _hasNoTurboBalance = turboBalance == BigInt.zero;
    _turboCredits = convertCreditsToLiteralString(turboBalance);
    _sufficentCreditsBalance = _costEstimateTurbo.totalCost <= _turboBalance;
    _computeIsTurboEnabled();
    _computeIsButtonEnabled();

    if (state is ConfirmingSnapshotCreation) {
      final stateAsConfirming = state as ConfirmingSnapshotCreation;
      logger.d('Refreshing turbo balance...');
      logger.d('Turbo balance: $_turboCredits - ($_turboBalance)');
      logger.d('Has no turbo balance: $_hasNoTurboBalance');
      logger
          .d('Sufficient balance to pay with turbo: $_sufficentCreditsBalance');
      logger.d('Upload method: $_uploadMethod');
      emit(
        stateAsConfirming.copyWith(
          turboCredits: _turboCredits,
          hasNoTurboBalance: _hasNoTurboBalance,
          sufficientBalanceToPayWithTurbo: _sufficentCreditsBalance,
          uploadMethod: _uploadMethod,
        ),
      );
    }
  }

  Future<void> _computeBalanceEstimate() async {
    final profileState = _profileCubit.state as ProfileLoggedIn;
    final wallet = profileState.wallet;

    final turboBalance =
        await turboBalanceRetriever.getBalance(wallet).catchError((e) {
      logger.e('Error while retrieving turbo balance', e);
      return BigInt.zero;
    });

    _turboBalance = turboBalance;
    _hasNoTurboBalance = turboBalance == BigInt.zero;
    _turboCredits = convertCreditsToLiteralString(turboBalance);
    _arBalance = convertCreditsToLiteralString(auth.currentUser!.walletBalance);
  }

  void _computeIsTurboEnabled() async {
    bool isTurboEnabled = appConfig.useTurboUpload;
    _isTurboUploadPossible = isTurboEnabled && _sufficentCreditsBalance;
  }

  void _computeIsSufficientBalance() {
    final profileState = _profileCubit.state as ProfileLoggedIn;

    bool sufficientBalanceToPayWithAR =
        profileState.walletBalance >= _costEstimateAr.totalCost;
    bool sufficientBalanceToPayWithTurbo =
        _costEstimateTurbo.totalCost <= _turboBalance;

    _sufficientArBalance = sufficientBalanceToPayWithAR;
    _sufficentCreditsBalance = sufficientBalanceToPayWithTurbo;
  }

  void _computeIsFreeThanksToTurbo() {
    final allowedDataItemSizeForTurbo = appConfig.allowedDataItemSizeForTurbo;
    final isFreeThanksToTurbo =
        _snapshotEntity!.data!.length <= allowedDataItemSizeForTurbo;
    _isFreeThanksToTurbo = isFreeThanksToTurbo;
  }

  Future<void> _emitConfirming({required int dataSize}) async {
    emit(ConfirmingSnapshotCreation(
      snapshotSize: dataSize,
      costEstimateAr: _costEstimateAr,
      costEstimateTurbo: _costEstimateTurbo,
      hasNoTurboBalance: _hasNoTurboBalance,
      isTurboUploadPossible: _isTurboUploadPossible,
      arBalance: _arBalance,
      turboCredits: _turboCredits,
      uploadMethod: _uploadMethod,
      isButtonToUploadEnabled: _isButtonToUploadEnabled,
      sufficientBalanceToPayWithAr: _sufficientArBalance,
      sufficientBalanceToPayWithTurbo: _sufficentCreditsBalance,
      isFreeThanksToTurbo: _isFreeThanksToTurbo,
    ));
  }

  void setUploadMethod(UploadMethod method) {
    logger.d('Upload method set to $method');
    _uploadMethod = method;

    _computeIsButtonEnabled();
    if (state is ConfirmingSnapshotCreation) {
      final stateAsConfirming = state as ConfirmingSnapshotCreation;
      emit(
        stateAsConfirming.copyWith(
          uploadMethod: method,
          isButtonToUploadEnabled: _isButtonToUploadEnabled,
        ),
      );
    }
  }

  void _computeIsButtonEnabled() {
    _isButtonToUploadEnabled = false;

    logger.d('Sufficient Balance To Pay With AR: $_sufficientArBalance');
    if (_uploadMethod == UploadMethod.ar && _sufficientArBalance) {
      logger.d('Enabling button for AR payment method');
      _isButtonToUploadEnabled = true;
    } else if (_uploadMethod == UploadMethod.turbo &&
        _isTurboUploadPossible &&
        _sufficentCreditsBalance) {
      logger.d('Enabling button for Turbo payment method');
      _isButtonToUploadEnabled = true;
    } else if (_isFreeThanksToTurbo) {
      logger.d('Enabling button for free upload using Turbo');
      _isButtonToUploadEnabled = true;
    } else {
      logger.d('Disabling button');
    }
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

    await _prepareAndSignTx(
      _snapshotEntity!,
    );

    try {
      emit(UploadingSnapshot());

      if (_useTurboUpload) {
        await _postTurboDataItem(
          dataItem: _preparedDataItem!,
        );
      } else {
        await _arweave.postTx(_preparedTx!);
      }

      emit(SnapshotUploadSuccess());
    } catch (err, stacktrace) {
      logger.e('Error while posting the snapshot transaction', err, stacktrace);
      emit(SnapshotUploadFailure());
    }
  }

  Future<void> _postTurboDataItem({required DataItem dataItem}) async {
    final profile = _profileCubit.state as ProfileLoggedIn;
    final wallet = profile.wallet;

    logger.d('Posting snapshot transaction for drive $_driveId');

    await turboService.postDataItem(
      dataItem: dataItem,
      wallet: wallet,
    );
  }

  void cancelSnapshotCreation() {
    logger.i('User cancelled the snapshot creation');

    _wasSnapshotDataComputingCanceled = true;
  }
}
