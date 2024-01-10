import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/hide/hide_event.dart';
import 'package:ardrive/blocs/hide/hide_state.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pst/pst.dart';

class HideBloc extends Bloc<HideEvent, HideState> {
  final ArweaveService _arweave;
  final ArDriveCrypto _crypto;
  final TurboUploadService _turboUploadService;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final TurboBalanceRetriever _turboBalanceRetriever;
  final PstService _pst;
  final PaymentService _paymentService;
  final ArDriveAuth _auth;
  final ConfigService _configService;

  List<DataItem> _dataItems = [];
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
  int _totalSize = 0;

  HideBloc({
    required ArweaveService arweaveService,
    required ArDriveCrypto crypto,
    required TurboUploadService turboUploadService,
    required DriveDao driveDao,
    required ProfileCubit profileCubit,
    required TurboBalanceRetriever turboBalanceRetriever,
    required PstService pst,
    required PaymentService paymentService,
    required ArDriveAuth auth,
    required ConfigService configService,
  })  : _arweave = arweaveService,
        _crypto = crypto,
        _turboUploadService = turboUploadService,
        _driveDao = driveDao,
        _profileCubit = profileCubit,
        _turboBalanceRetriever = turboBalanceRetriever,
        _pst = pst,
        _paymentService = paymentService,
        _auth = auth,
        _configService = configService,
        super(const InitialHideState()) {
    on<HideFileEvent>(_onHideFileEvent);
    on<HideFolderEvent>(_onHideFolderEvent);
    on<UnhideFileEvent>(_onUnhideFileEvent);
    on<UnhideFolderEvent>(_onUnhideFolderEvent);
    on<ConfirmUploadEvent>(_onConfirmUploadEvent);
    on<SelectUploadMethodEvent>(_onSelectUploadMethodEvent);
    on<RefreshTurboBalanceEvent>(_refreshTurboBalance);
    on<ErrorEvent>(_onErrorEvent);
  }

  bool get _useTurboUpload =>
      _uploadMethod == UploadMethod.turbo || _isFreeThanksToTurbo;

  AppConfig get _appConfig => _configService.config;

  Future<void> _onHideFileEvent(
    HideFileEvent event,
    Emitter<HideState> emit,
  ) async {
    emit(const PreparingAndSigningHideState(hideAction: HideAction.hideFile));

    final profile = _profileCubit.state as ProfileLoggedIn;
    late DataItem fileDataItem;

    final FileEntry currentFile = await _driveDao
        .fileById(
          driveId: event.driveId,
          fileId: event.fileId,
        )
        .getSingle();
    final newFile = currentFile.copyWith(
      isHidden: true,
      lastUpdated: DateTime.now(),
    );
    final fileEntity = newFile.asEntity();

    final driveKey = await _driveDao.getDriveKey(
      event.driveId,
      profile.cipherKey,
    );
    final fileKey = driveKey != null
        ? await _crypto.deriveFileKey(driveKey, currentFile.id)
        : null;
    fileDataItem = await _arweave.prepareEntityDataItem(
      fileEntity,
      profile.wallet,
      key: fileKey,
    );

    await _computeCostEstimate();
    await _computeBalanceEstimate();
    _computeIsFreeThanksToTurbo();
    _computeIsSufficientBalance();

    Future<void> saveEntitiesToDb() async {
      await _driveDao.writeToFile(newFile);
      fileEntity.txId = fileDataItem.id;

      await _driveDao.insertFileRevision(fileEntity.toRevisionCompanion(
        performedAction: RevisionAction.hide,
      ));
    }

    final dataItems = [fileDataItem];
    _dataItems = dataItems;

    logger.d(
      'Hiding file ${event.fileId} in drive ${event.driveId}'
      ' with JSON: ${fileEntity.toJson()}',
    );

    emit(
      ConfirmingHideState(
        uploadMethod: UploadMethod.turbo,
        costEstimateTurbo: _costEstimateTurbo,
        costEstimateAr: _costEstimateAr,
        hasNoTurboBalance: _hasNoTurboBalance,
        isTurboUploadPossible: _isTurboUploadPossible,
        arBalance: _arBalance,
        sufficientArBalance: _sufficientArBalance,
        turboCredits: _turboCredits,
        sufficentCreditsBalance: _sufficentCreditsBalance,
        isFreeThanksToTurbo: _isFreeThanksToTurbo,
        isButtonToUploadEnabled: _isButtonToUploadEnabled,
        hideAction: HideAction.hideFile,
        dataItems: dataItems,
        saveEntitiesToDb: saveEntitiesToDb,
      ),
    );
  }

  Future<void> _onHideFolderEvent(
    HideFolderEvent event,
    Emitter<HideState> emit,
  ) async {
    emit(const PreparingAndSigningHideState(hideAction: HideAction.hideFolder));

    logger.d('Hiding folder ${event.folderId} in drive ${event.driveId}');
    final profile = _profileCubit.state as ProfileLoggedIn;
    late DataItem folderDataItem;

    final FolderEntry currentFolder = await _driveDao
        .folderById(
          driveId: event.driveId,
          folderId: event.folderId,
        )
        .getSingle();
    final newFolder = currentFolder.copyWith(
      isHidden: true,
      lastUpdated: DateTime.now(),
    );
    final folderEntity = newFolder.asEntity();

    final driveKey = await _driveDao.getDriveKey(
      event.driveId,
      profile.cipherKey,
    );
    final folderKey = driveKey;
    folderDataItem = await _arweave.prepareEntityDataItem(
      folderEntity,
      profile.wallet,
      key: folderKey,
    );

    final dataItems = [folderDataItem];

    Future<void> saveEntitiesToDb() async {
      await _driveDao.writeToFolder(newFolder);
      folderEntity.txId = folderDataItem.id;

      await _driveDao.insertFolderRevision(folderEntity.toRevisionCompanion(
        performedAction: RevisionAction.hide,
      ));
    }

    await _computeCostEstimate();
    await _computeBalanceEstimate();
    _computeIsFreeThanksToTurbo();
    _computeIsSufficientBalance();

    emit(
      ConfirmingHideState(
        uploadMethod: UploadMethod.turbo,
        costEstimateTurbo: _costEstimateTurbo,
        costEstimateAr: _costEstimateAr,
        hasNoTurboBalance: _hasNoTurboBalance,
        isTurboUploadPossible: _isTurboUploadPossible,
        arBalance: _arBalance,
        sufficientArBalance: _sufficientArBalance,
        turboCredits: _turboCredits,
        sufficentCreditsBalance: _sufficentCreditsBalance,
        isFreeThanksToTurbo: _isFreeThanksToTurbo,
        isButtonToUploadEnabled: _isButtonToUploadEnabled,
        hideAction: HideAction.hideFolder,
        dataItems: dataItems,
        saveEntitiesToDb: saveEntitiesToDb,
      ),
    );
  }

  Future<void> _onUnhideFileEvent(
    UnhideFileEvent event,
    Emitter<HideState> emit,
  ) async {
    emit(const PreparingAndSigningHideState(hideAction: HideAction.unhideFile));

    final profile = _profileCubit.state as ProfileLoggedIn;
    late DataItem fileDataItem;

    final FileEntry currentFile = await _driveDao
        .fileById(
          driveId: event.driveId,
          fileId: event.fileId,
        )
        .getSingle();
    final newFile = currentFile.copyWith(
      isHidden: false,
      lastUpdated: DateTime.now(),
    );
    final fileEntity = newFile.asEntity();

    final driveKey = await _driveDao.getDriveKey(
      event.driveId,
      profile.cipherKey,
    );
    final fileKey = driveKey != null
        ? await _crypto.deriveFileKey(driveKey, currentFile.id)
        : null;
    fileDataItem = await _arweave.prepareEntityDataItem(
      fileEntity,
      profile.wallet,
      key: fileKey,
    );

    final dataItems = [fileDataItem];

    Future<void> saveEntitiesToDb() async {
      await _driveDao.writeToFile(newFile);
      fileEntity.txId = fileDataItem.id;

      await _driveDao.insertFileRevision(fileEntity.toRevisionCompanion(
        performedAction: RevisionAction.unhide,
      ));
    }

    await _computeCostEstimate();
    await _computeBalanceEstimate();
    _computeIsFreeThanksToTurbo();
    _computeIsSufficientBalance();

    emit(
      ConfirmingHideState(
        uploadMethod: UploadMethod.turbo,
        costEstimateTurbo: _costEstimateTurbo,
        costEstimateAr: _costEstimateAr,
        hasNoTurboBalance: _hasNoTurboBalance,
        isTurboUploadPossible: _isTurboUploadPossible,
        arBalance: _arBalance,
        sufficientArBalance: _sufficientArBalance,
        turboCredits: _turboCredits,
        sufficentCreditsBalance: _sufficentCreditsBalance,
        isFreeThanksToTurbo: _isFreeThanksToTurbo,
        isButtonToUploadEnabled: _isButtonToUploadEnabled,
        hideAction: HideAction.unhideFile,
        dataItems: dataItems,
        saveEntitiesToDb: saveEntitiesToDb,
      ),
    );
  }

  Future<void> _onUnhideFolderEvent(
    UnhideFolderEvent event,
    Emitter<HideState> emit,
  ) async {
    emit(const PreparingAndSigningHideState(
      hideAction: HideAction.unhideFolder,
    ));

    logger.d('Unhiding folder ${event.folderId} in drive ${event.driveId}');
    final profile = _profileCubit.state as ProfileLoggedIn;
    late DataItem folderDataItem;

    final FolderEntry currentFolder = await _driveDao
        .folderById(
          driveId: event.driveId,
          folderId: event.folderId,
        )
        .getSingle();
    final newFolder = currentFolder.copyWith(
      isHidden: false,
      lastUpdated: DateTime.now(),
    );
    final folderEntity = newFolder.asEntity();

    logger.d('Unhiding folder with JSON: ${folderEntity.toJson()}');

    final driveKey = await _driveDao.getDriveKey(
      event.driveId,
      profile.cipherKey,
    );
    final folderKey = driveKey;
    folderDataItem = await _arweave.prepareEntityDataItem(
      folderEntity,
      profile.wallet,
      key: folderKey,
    );

    final dataItems = [folderDataItem];

    Future<void> saveEntitiesToDb() async {
      await _driveDao.writeToFolder(newFolder);
      folderEntity.txId = folderDataItem.id;

      await _driveDao.insertFolderRevision(folderEntity.toRevisionCompanion(
        performedAction: RevisionAction.unhide,
      ));
    }

    await _computeCostEstimate();
    await _computeBalanceEstimate();
    _computeIsFreeThanksToTurbo();
    _computeIsSufficientBalance();

    emit(
      ConfirmingHideState(
        uploadMethod: UploadMethod.turbo,
        costEstimateTurbo: _costEstimateTurbo,
        costEstimateAr: _costEstimateAr,
        hasNoTurboBalance: _hasNoTurboBalance,
        isTurboUploadPossible: _isTurboUploadPossible,
        arBalance: _arBalance,
        sufficientArBalance: _sufficientArBalance,
        turboCredits: _turboCredits,
        sufficentCreditsBalance: _sufficentCreditsBalance,
        isFreeThanksToTurbo: _isFreeThanksToTurbo,
        isButtonToUploadEnabled: _isButtonToUploadEnabled,
        hideAction: HideAction.unhideFolder,
        dataItems: dataItems,
        saveEntitiesToDb: saveEntitiesToDb,
      ),
    );
  }

  Future<void> _onConfirmUploadEvent(
    ConfirmUploadEvent event,
    Emitter<HideState> emit,
  ) async {
    final state = this.state as ConfirmingHideState;
    final profile = _profileCubit.state as ProfileLoggedIn;
    final dataItems = state.dataItems;

    emit(UploadingHideState(hideAction: state.hideAction));

    await _driveDao.transaction(() async {
      final dataBundle = await DataBundle.fromDataItems(
        items: dataItems,
      );

      if (_useTurboUpload) {
        final hideTx = await _arweave.prepareBundledDataItem(
          dataBundle,
          profile.wallet,
        );
        await _turboUploadService.postDataItem(
          dataItem: hideTx,
          wallet: profile.wallet,
        );
      } else {
        final hideTx = await _arweave.prepareDataBundleTx(
          dataBundle,
          profile.wallet,
        );
        await _arweave.postTx(hideTx);
      }

      await state.saveEntitiesToDb();

      emit(SuccessHideState(hideAction: state.hideAction));
    });
  }

  Future<void> _onSelectUploadMethodEvent(
    SelectUploadMethodEvent event,
    Emitter<HideState> emit,
  ) async {
    final state = this.state as ConfirmingHideState;

    _uploadMethod = event.uploadMethod;

    emit(
      state.copyWith(
        uploadMethod: event.uploadMethod,
      ),
    );
  }

  void _onErrorEvent(
    ErrorEvent event,
    Emitter<HideState> emit,
  ) {
    emit(FailureHideState(hideAction: event.hideAction));
  }

  void _computeIsFreeThanksToTurbo() {
    final allowedDataItemSizeForTurbo = _appConfig.allowedDataItemSizeForTurbo;
    final forceNoFreeThanksToTurbo = _appConfig.forceNoFreeThanksToTurbo;
    final isFreeThanksToTurbo = _totalSize <= allowedDataItemSizeForTurbo;
    _isFreeThanksToTurbo = isFreeThanksToTurbo && !forceNoFreeThanksToTurbo;
  }

  Future<void> _computeBalanceEstimate() async {
    final ProfileLoggedIn profileState = _profileCubit.state as ProfileLoggedIn;
    final Wallet wallet = profileState.wallet;

    final BigInt? fakeTurboCredits = _appConfig.fakeTurboCredits;

    final BigInt turboBalance = fakeTurboCredits ??
        await _turboBalanceRetriever.getBalance(wallet).catchError((e) {
          logger.e('Error while retrieving turbo balance', e);
          return BigInt.zero;
        });

    logger.d('Balance before topping up: $turboBalance');

    _turboBalance = turboBalance;
    _hasNoTurboBalance = turboBalance == BigInt.zero;
    _turboCredits = convertWinstonToLiteralString(turboBalance);
    _arBalance = convertWinstonToLiteralString(_auth.currentUser.walletBalance);
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

  Future<void> _refreshTurboBalance(
    RefreshTurboBalanceEvent event,
    Emitter<HideState> emit,
  ) async {
    final profileState = _profileCubit.state as ProfileLoggedIn;
    final wallet = profileState.wallet;
    final state = this.state as ConfirmingHideState;

    final BigInt? fakeTurboCredits = _appConfig.fakeTurboCredits;

    /// necessary to wait for backend update the balance
    await Future.delayed(const Duration(seconds: 2));

    final BigInt turboBalance = fakeTurboCredits ??
        await _turboBalanceRetriever.getBalance(wallet).catchError((e) {
          logger.e('Error while retrieving turbo balance', e);
          return BigInt.zero;
        });

    _turboBalance = turboBalance;
    _hasNoTurboBalance = turboBalance == BigInt.zero;
    _turboCredits = convertWinstonToLiteralString(turboBalance);
    _sufficentCreditsBalance = _costEstimateTurbo.totalCost <= _turboBalance;
    _computeIsTurboEnabled();
    _computeIsButtonEnabled();

    emit(
      state.copyWith(
        hasNoTurboBalance: _hasNoTurboBalance,
        turboCredits: _turboCredits,
        sufficentCreditsBalance: _sufficentCreditsBalance,
        isTurboUploadPossible: _isTurboUploadPossible,
      ),
    );
  }

  void _computeIsTurboEnabled() async {
    bool isTurboEnabled = _appConfig.useTurboUpload;
    _isTurboUploadPossible = isTurboEnabled && _sufficentCreditsBalance;
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

  Future<void> _computeCostEstimate() async {
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

    final dataItems = _dataItems;
    _totalSize = dataItems.fold<int>(
      0,
      (previousValue, element) => previousValue + element.getSize(),
    );

    _costEstimateAr = await costCalculatorForAr.calculateCost(
      totalSize: _totalSize,
    );
    _costEstimateTurbo = await costCalculatorForTurbo.calculateCost(
      totalSize: _totalSize,
    );
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    add(ErrorEvent(
      error: error,
      stackTrace: stackTrace,
      hideAction: state.hideAction,
    ));
    super.onError(error, stackTrace);
  }
}
