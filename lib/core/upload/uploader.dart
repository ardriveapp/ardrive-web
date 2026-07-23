import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/blocs/upload/models/upload_plan.dart';
import 'package:ardrive/blocs/upload/models/web_folder.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/blocs/upload/upload_handles/handles.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive/turbo/models/turbo_free_allowance.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/size_utils.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:arweave/arweave.dart';
import 'package:tuple/tuple.dart';

import '../../turbo/services/payment_service.dart';

class ArDriveUploaderFromHandles {
  final BundleUploader _bundleUploader;
  final FileV2Uploader _fileV2Uploader;
  final Future<void> Function(BundleUploadHandle handle) _prepareBundle;
  final Future<void> Function(FileV2UploadHandle handle) _prepareFile;
  final Future<void> Function(BundleUploadHandle handle) _onFinishBundleUpload;
  final Future<void> Function(FileV2UploadHandle handle) _onFinishFileUpload;
  final Future<void> Function(BundleUploadHandle handle, Object error)
      _onUploadBundleError;
  final Future<void> Function(FileV2UploadHandle handle, Object error)
      _onUploadFileError;

  ArDriveUploaderFromHandles({
    required BundleUploader bundleUploader,
    required FileV2Uploader fileV2Uploader,
    required Future<void> Function(BundleUploadHandle handle) prepareBundle,
    required Future<void> Function(FileV2UploadHandle handle) prepareFile,
    required Future<void> Function(BundleUploadHandle handle)
        onFinishBundleUpload,
    required Future<void> Function(FileV2UploadHandle handle)
        onFinishFileUpload,
    required Future<void> Function(BundleUploadHandle handle, Object error)
        onUploadBundleError,
    required Future<void> Function(FileV2UploadHandle handle, Object error)
        onUploadFileError,
  })  : _bundleUploader = bundleUploader,
        _fileV2Uploader = fileV2Uploader,
        _prepareBundle = prepareBundle,
        _prepareFile = prepareFile,
        _onFinishBundleUpload = onFinishBundleUpload,
        _onFinishFileUpload = onFinishFileUpload,
        _onUploadBundleError = onUploadBundleError,
        _onUploadFileError = onUploadFileError;

  Stream<double> uploadFromHandles({
    List<BundleUploadHandle> bundleHandles = const [],
    List<FileV2UploadHandle> fileV2Handles = const [],
    bool enableLogs = true,
  }) async* {
    final List<double> progresses = List.filled(
      bundleHandles.length + fileV2Handles.length,
      0.0,
    );

    int index = 0;

    for (final bundleHandle in bundleHandles) {
      try {
        await _prepareBundle(bundleHandle);
      } catch (e) {
        logger.e('Error preparing bundle', e);
        _onUploadBundleError(bundleHandle, e);
        return;
      }

      Stopwatch stopwatch = Stopwatch()..start();
      int dataSize = bundleHandle.size;

      await for (var progress in _uploadItem(
        index: index++,
        itemHandle: bundleHandle,
        upload: _bundleUploader.upload,
        onFinishUpload: _onFinishBundleUpload,
        onUploadError: _onUploadBundleError,
        dispose: (handle) =>
            handle.clearBundleData(useTurbo: _bundleUploader.useTurbo),
      )) {
        progresses[progress.item1] = progress.item2;
        yield progresses.reduce((a, b) => a + b) / progresses.length;
      }

      stopwatch.stop();

      if (enableLogs) {
        final elapsedSeconds = stopwatch.elapsedMilliseconds / 1000.0;
        final uploadSpeed = dataSize / elapsedSeconds;

        logger.i('Total time elapsed: $elapsedSeconds seconds. '
            'Average upload speed: ${filesize(uploadSpeed.toInt())}/sec');
      }
    }

    for (final fileV2Handle in fileV2Handles) {
      logger.i('Uploading fileV2Handle...');

      try {
        await _prepareFile(fileV2Handle);
      } catch (e) {
        logger.e('Error preparing file', e);
        _onUploadFileError(fileV2Handle, e);
        return;
      }

      final stopwatch = Stopwatch()..start();

      final dataSize = fileV2Handle.size;

      await for (var progress in _uploadItem(
        index: index++,
        itemHandle: fileV2Handle,
        upload: _fileV2Uploader.upload,
        onFinishUpload: _onFinishFileUpload,
        onUploadError: _onUploadFileError,
        dispose: (handle) => handle.dispose(),
      )) {
        progresses[progress.item1] = progress.item2;
        yield progresses.reduce((a, b) => a + b) / progresses.length;
      }

      stopwatch.stop();

      if (enableLogs) {
        final elapsedSeconds = stopwatch.elapsedMilliseconds / 1000.0;
        final uploadSpeed = dataSize / elapsedSeconds;

        logger.i('Total time elapsed: $elapsedSeconds seconds '
            'Average upload speed: ${filesize(uploadSpeed.toInt())}/sec');
      }
    }
  }

  Stream<Tuple2<int, double>> _uploadItem<T>({
    required T itemHandle,
    required int index,
    required Stream<double> Function(T handle) upload,
    required Future<void> Function(T handle) onFinishUpload,
    required Future<void> Function(T handle, Object error) onUploadError,
    required void Function(T handle) dispose,
  }) async* {
    try {
      await for (var progress in upload(itemHandle).handleError((e, s) {
        logger.e('[UPLOADER]: Handling error on ArDriveUploader', e, s);

        onUploadError(itemHandle, e).then((value) => dispose(itemHandle));

        // Breaks the upload
        throw e;
      })) {
        yield Tuple2(index, progress);
      }

      logger.i('[UPLOADER]: Finished uploading item handle '
          '[UPLOADER]: Disposing item handle');

      onFinishUpload(itemHandle).then((value) => dispose(itemHandle));
    } catch (e, stacktrace) {
      logger.e(
        '[UPLOADER]: Disposing item handleError in ${itemHandle.toString()} upload',
        e,
        stacktrace,
      );

      onUploadError(itemHandle, e);

      rethrow;
    }
  }
}

class BundleUploader extends Uploader<BundleUploadHandle> {
  final TurboUploader _turbo;
  final ArweaveBundleUploader _arweave;
  final bool useTurbo;

  late Uploader _uploader;

  BundleUploader(this._turbo, this._arweave, this.useTurbo) {
    logger.i('Creating BundleUploader');

    if (useTurbo) {
      logger.i('Using TurboUploader');

      _uploader = _turbo;
    } else {
      logger.i('Using ArweaveBundleUploader');

      _uploader = _arweave;
    }
  }

  @override
  Stream<double> upload(BundleUploadHandle handle) async* {
    yield* _uploader.upload(handle);
  }

  @override
  String toString() {
    return 'BundleUploader{_turbo: $_turbo, _arweave: $_arweave, _useTurbo: $useTurbo}';
  }
}

abstract class Uploader<T extends UploadHandle> {
  Stream<double> upload(
    T handle,
  );
}

class TurboUploader implements Uploader<BundleUploadHandle> {
  final TurboUploadService _turbo;
  final Wallet _wallet;

  TurboUploader(this._turbo, this._wallet);

  @override
  Stream<double> upload(handle) async* {
    yield* _turbo
        .postDataItemWithProgress(
            dataItem: handle.bundleDataItem, wallet: _wallet)
        .map((progress) {
      handle.setUploadProgress(progress);
      return progress;
    });
  }
}

class ArweaveBundleUploader implements Uploader<BundleUploadHandle> {
  final Arweave _arweave;

  ArweaveBundleUploader(this._arweave);

  @override
  Stream<double> upload(handle) async* {
    yield* _arweave.transactions
        .upload(handle.bundleTx,
            maxConcurrentUploadCount: maxConcurrentUploadCount)
        .map((upload) {
      handle.setUploadProgress(upload.progress);
      return upload.progress;
    });
  }
}

class FileV2Uploader implements Uploader<FileV2UploadHandle> {
  final Arweave _arweave;
  final ArweaveService _arweaveService;

  FileV2Uploader(this._arweave, this._arweaveService);

  @override
  Stream<double> upload(handle) async* {
    await _arweaveService
        .postTx(handle.entityTx)
        .onError((error, stackTrace) => handle.hasError = true);

    yield* _arweave.transactions
        .upload(handle.dataTx, maxConcurrentUploadCount: 1)
        .map((upload) {
      handle.uploadProgress = upload.progress;
      return upload.progress;
    });
  }
}

class UploadPreparer {
  final UploadPlanUtils _uploadPlanUtils;

  UploadPreparer({
    required UploadPlanUtils uploadPlanUtils,
  }) : _uploadPlanUtils = uploadPlanUtils;

  Future<UploadPlansPreparation> prepareFileUpload(UploadParams params) async {
    final uploadPlanForAR = await _mountUploadPlan(
      params: params,
      method: UploadMethod.ar,
    );

    final uploadPlanForTurbo = await _mountUploadPlan(
      params: params,
      method: UploadMethod.turbo,
    );

    return UploadPlansPreparation(
      uploadPlanForAr: uploadPlanForAR,
      uploadPlanForTurbo: uploadPlanForTurbo,
    );
  }

  Future<UploadPlan> _mountUploadPlan({
    required UploadParams params,
    required UploadMethod method,
  }) async {
    final uploadPlan = await _uploadPlanUtils.filesToUploadPlan(
      targetFolder: params.targetFolder,
      targetDrive: params.targetDrive,
      files: params.files,
      cipherKey: params.user.cipherKey,
      wallet: params.user.wallet,
      conflictingFiles: params.conflictingFiles,
      foldersByPath: params.foldersByPath,
      useTurbo: method == UploadMethod.turbo,
    );

    return uploadPlan;
  }
}

class UploadPaymentEvaluator {
  final TurboBalanceRetriever _turboBalanceRetriever;
  final UploadCostEstimateCalculatorForAR _uploadCostEstimateCalculatorForAR;
  final TurboUploadCostCalculator _turboUploadCostCalculator;
  final ArDriveAuth _auth;
  final SizeUtils sizeUtils = SizeUtils();
  final AppConfig _appConfig;
  final TurboUploadService? _turboUploadService;

  UploadPaymentEvaluator({
    required TurboBalanceRetriever turboBalanceRetriever,
    required UploadCostEstimateCalculatorForAR
        uploadCostEstimateCalculatorForAR,
    required ArDriveAuth auth,
    required TurboUploadCostCalculator turboUploadCostCalculator,
    required AppConfig appConfig,
    TurboUploadService? turboUploadService,
  })  : _turboBalanceRetriever = turboBalanceRetriever,
        _appConfig = appConfig,
        _uploadCostEstimateCalculatorForAR = uploadCostEstimateCalculatorForAR,
        _auth = auth,
        _turboUploadService = turboUploadService,
        _turboUploadCostCalculator = turboUploadCostCalculator;

  /// The maximum size, in bytes, of an item eligible for a free Turbo upload.
  /// Prefers the server-reported value from GET /v1/info (via the upload
  /// service); falls back to the config value when no service is wired.
  int get _maxFreeItemBytes =>
      _turboUploadService?.maxFreeItemSizeBytes ??
      _appConfig.allowedDataItemSizeForTurbo;

  /// Even if this feature flag is off, it will be possible to upload using turbo
  /// for free files
  bool get _canUseTurbo => _appConfig.useTurboUpload;
  bool _isTurboAvailableToUploadAllFiles = true;

  Future<UploadPaymentInfo> getUploadPaymentInfoForEntities({
    required DataItem dataItem,
  }) async {
    final dataItemSize = dataItem.getSize();

    UploadMethod uploadMethod;

    int totalSize = 0;

    TurboBalanceInterface turboBalance;

    turboBalance = await _getTurboBalance(canUseTurbo: _canUseTurbo);
    final turboCostEstimate = await _turboUploadCostCalculator.calculateCost(
      totalSize: dataItemSize,
    );

    /// Calculate the upload cost with AR (D2N). If the gateway is
    /// unavailable, fall back to a zero estimate so the modal can still
    /// show Turbo as an option instead of crashing entirely.
    UploadCostEstimate arCostEstimate;
    try {
      arCostEstimate = await _uploadCostEstimateCalculatorForAR.calculateCost(
        totalSize: dataItemSize,
      );
    } catch (e) {
      logger.e('Failed to get AR cost estimate, falling back to zero', e);
      arCostEstimate = UploadCostEstimate.zero();
    }

    final allowedDataItemSizeForTurbo = _maxFreeItemBytes;

    /// An item is free only if it is both small enough to qualify AND the
    /// wallet still has free allowance to cover it. Size alone would promise
    /// "free" to a user whose pool is used up, and then fail with a 402.
    final freeAllowance = await _getFreeAllowance(canUseTurbo: _canUseTurbo);
    final freeStatus = freeUploadStatusFor(
      isSizeEligible: dataItemSize <= allowedDataItemSizeForTurbo,
      byteCount: dataItemSize,
      allowance: freeAllowance,
    );

    uploadMethod = await _determineUploadMethod(
      turboBalance.balance,
      dataItemSize,
      allowedDataItemSizeForTurbo,
      _isTurboAvailableToUploadAllFiles,
      freeAllowance,
    );

    return UploadPaymentInfo(
      isTurboAvailable: _isTurboAvailableToUploadAllFiles,
      defaultPaymentMethod: uploadMethod,
      isUploadEligibleToTurbo: true,
      arCostEstimate: arCostEstimate,
      turboCostEstimate: turboCostEstimate,
      freeStatus: freeStatus,
      totalSize: totalSize,
      turboBalance: turboBalance,
    );
  }

  Future<UploadPaymentInfo> getUploadPaymentInfoForUploadPlans({
    required UploadPlan uploadPlanForAR,
    required UploadPlan uploadPlanForTurbo,
  }) async {
    UploadMethod uploadMethod;

    int totalSize = 0;

    TurboBalanceInterface turboBalance;

    /// Check the balance of the user
    /// If we can't get the balance, turbo won't be available
    turboBalance = await _getTurboBalance(canUseTurbo: _canUseTurbo);

    final arBundleSizes = await sizeUtils
        .getSizeOfAllBundles(uploadPlanForAR.bundleUploadHandles);
    final arFileSizes = await sizeUtils
        .getSizeOfAllV2Files(uploadPlanForAR.fileV2UploadHandles);

    bool isUploadEligibleToTurbo =
        uploadPlanForTurbo.fileV2UploadHandles.isEmpty &&
            uploadPlanForTurbo.bundleUploadHandles.isNotEmpty;

    UploadCostEstimate turboCostEstimate = UploadCostEstimate.zero();

    int turboBundleSizes = 0;

    /// Calculate the upload with Turbo if possible
    if (isUploadEligibleToTurbo) {
      turboBundleSizes = await sizeUtils
          .getSizeOfAllBundles(uploadPlanForTurbo.bundleUploadHandles);

      try {
        turboCostEstimate = await _turboUploadCostCalculator.calculateCost(
          totalSize: turboBundleSizes,
        );
      } catch (e) {
        _isTurboAvailableToUploadAllFiles = false;
      }
    }

    /// Calculate the upload cost with AR (D2N). If the gateway is
    /// unavailable, fall back to a zero estimate so the modal can still
    /// show Turbo as an option instead of crashing entirely.
    UploadCostEstimate arCostEstimate;
    try {
      arCostEstimate = await _uploadCostEstimateCalculatorForAR.calculateCost(
        totalSize: arBundleSizes + arFileSizes,
      );
    } catch (e) {
      logger.e('Failed to get AR cost estimate, falling back to zero', e);
      arCostEstimate = UploadCostEstimate.zero();
    }

    final freeAllowance = await _getFreeAllowance(canUseTurbo: _canUseTurbo);

    /// Every item being small enough is not sufficient — the wallet's free
    /// pool has to cover the whole upload too. Turbo bills the entire upload
    /// once the pool runs out, so partial coverage is not free either.
    var freeStatus = FreeUploadStatus.notEligible;

    if (isUploadEligibleToTurbo) {
      final allowedDataItemSizeForTurbo = _maxFreeItemBytes;

      freeStatus = freeUploadStatusFor(
        isSizeEligible: uploadPlanForTurbo.bundleUploadHandles.every(
          (bundle) => bundle.fileDataItemUploadHandles.every(
            (file) => file.size <= allowedDataItemSizeForTurbo,
          ),
        ),
        byteCount: turboBundleSizes,
        allowance: freeAllowance,
      );
    }

    final isFreeUploadPossibleUsingTurbo = freeStatus == FreeUploadStatus.free;

    // Checking isFreeUploadPossibleUsingTurbo uses the 100KB file size check
    // against the date, but using _determineUploadMethod() additionally uses the
    // Turbo bundle headers as part of the size check. A 100KB file might be
    // larger than _appConfig.allowedDataItemSizeForTurbo due to the headers,
    // so we need to catch that here.
    uploadMethod = isFreeUploadPossibleUsingTurbo
        ? UploadMethod.turbo
        : await _determineUploadMethod(
            turboBalance.balance,
            turboBundleSizes,
            _maxFreeItemBytes,
            _isTurboAvailableToUploadAllFiles,
            freeAllowance,
          );

    if (uploadMethod == UploadMethod.turbo) {
      totalSize = turboBundleSizes;
    } else if (uploadMethod == UploadMethod.ar) {
      totalSize = arBundleSizes + arFileSizes;
    }

    logger.d('Upload payment info prepared with method: $uploadMethod, '
        'total size: $totalSize, turbo balance: $turboBalance');
    return UploadPaymentInfo(
      isTurboAvailable: _isTurboAvailableToUploadAllFiles,
      defaultPaymentMethod: uploadMethod,
      isUploadEligibleToTurbo: isUploadEligibleToTurbo,
      arCostEstimate: arCostEstimate,
      turboCostEstimate: turboCostEstimate,
      freeStatus: freeStatus,
      totalSize: totalSize,
      turboBalance: turboBalance,
    );
  }

  /// The wallet's remaining free-upload allowance, honouring the turbo
  /// feature flag. Never throws — see [TurboBalanceRetriever.getFreeAllowance].
  Future<TurboFreeAllowance> getFreeAllowance() =>
      _getFreeAllowance(canUseTurbo: _canUseTurbo);

  /// The maximum size of an item eligible for a free upload, preferring
  /// Turbo's server-reported value over the static config one.
  int get maxFreeItemBytes => _maxFreeItemBytes;

  /// The wallet's remaining free-upload allowance for this preparation.
  ///
  /// Fetched per preparation rather than cached like the item-size limit:
  /// the limit is static server config, but the allowance is mutable
  /// per-wallet state that other devices and uploads consume.
  Future<TurboFreeAllowance> _getFreeAllowance({
    required bool canUseTurbo,
  }) async {
    if (!canUseTurbo) {
      return const TurboFreeAllowance.unknown();
    }

    return _turboBalanceRetriever.getFreeAllowance(_auth.currentUser.wallet);
  }

  Future<TurboBalanceInterface> _getTurboBalance({
    required bool canUseTurbo,
  }) async {
    if (!canUseTurbo) {
      _isTurboAvailableToUploadAllFiles = false;
      return TurboBalanceInterface(
        balance: BigInt.zero,
        paidBy: [],
      );
    }

    try {
      return await _turboBalanceRetriever
          .getBalanceAndPaidBy(_auth.currentUser.wallet);
    } catch (e, stacktrace) {
      logger.e(
        'An error occurred while getting the turbo balance',
        e,
        stacktrace,
      );
      _isTurboAvailableToUploadAllFiles = false;
      return TurboBalanceInterface(
        balance: BigInt.zero,
        paidBy: [],
      );
    }
  }

  Future<UploadMethod> _determineUploadMethod(
    BigInt turboBalance,
    int turboBundleSizes,
    int allowedSizeForTurbo,
    bool isTurboAvailableToUploadAllFiles,
    TurboFreeAllowance freeAllowance,
  ) async {
    bool isFreeUploadPossibleUsingTurbo =
        turboBundleSizes <= allowedSizeForTurbo &&
            freeAllowance.covers(turboBundleSizes);

    if (isFreeUploadPossibleUsingTurbo) {
      return UploadMethod.turbo;
    }

    try {
      final turboCostEstimate = await _turboUploadCostCalculator.calculateCost(
        totalSize: turboBundleSizes,
      );

      if ((isTurboAvailableToUploadAllFiles &&
              turboBalance >= turboCostEstimate.totalCost) ||
          isFreeUploadPossibleUsingTurbo) {
        return UploadMethod.turbo;
      } else {
        return UploadMethod.ar;
      }
    } catch (e) {
      _isTurboAvailableToUploadAllFiles = false;

      return UploadMethod.ar;
    }
  }
}

class UploadPreparation {
  final UploadPlansPreparation uploadPlansPreparation;
  final UploadPaymentInfo uploadPaymentInfo;

  UploadPreparation({
    required this.uploadPlansPreparation,
    required this.uploadPaymentInfo,
  });
}

class UploadPaymentInfo {
  final UploadMethod defaultPaymentMethod;
  final bool isUploadEligibleToTurbo;
  final bool isTurboAvailable;
  final UploadCostEstimate arCostEstimate;
  final UploadCostEstimate turboCostEstimate;
  final int totalSize;
  final TurboBalanceInterface turboBalance;

  /// Whether this upload is free, and if not, why not. Single source of truth
  /// for the booleans below, which cannot therefore contradict each other.
  final FreeUploadStatus freeStatus;

  UploadPaymentInfo({
    required this.defaultPaymentMethod,
    required this.isUploadEligibleToTurbo,
    required this.arCostEstimate,
    required this.turboCostEstimate,
    required this.freeStatus,
    required this.totalSize,
    required this.isTurboAvailable,
    required this.turboBalance,
  });

  bool get isFreeUploadPossibleUsingTurbo =>
      freeStatus == FreeUploadStatus.free;

  /// Would have been free on size, but the wallet's allowance is known to be
  /// used up. False when the allowance simply could not be determined.
  bool get isFreeAllowanceExhausted =>
      freeStatus == FreeUploadStatus.allowanceUsedUp;

  /// Every item is small enough to qualify, regardless of allowance left.
  bool get isSizeEligibleForFree => freeStatus != FreeUploadStatus.notEligible;
}

class UploadPlansPreparation {
  final UploadPlan uploadPlanForAr;
  final UploadPlan uploadPlanForTurbo;

  UploadPlansPreparation({
    required this.uploadPlanForAr,
    required this.uploadPlanForTurbo,
  });
}

class ArDriveUploadPreparationManager {
  final UploadPreparer _uploadPreparer;
  final UploadPaymentEvaluator _uploadPaymentEvaluator;

  ArDriveUploadPreparationManager({
    required UploadPreparer uploadPreparer,
    required UploadPaymentEvaluator uploadPreparePaymentOptions,
  })  : _uploadPreparer = uploadPreparer,
        _uploadPaymentEvaluator = uploadPreparePaymentOptions;

  /// The wallet's remaining free-upload allowance, for callers that decide
  /// free-vs-paid themselves instead of going through [prepareUpload].
  /// Returns [TurboFreeAllowance.unknown] rather than throwing.
  Future<TurboFreeAllowance> getFreeAllowance() =>
      _uploadPaymentEvaluator.getFreeAllowance();

  /// The maximum size of an item eligible for a free upload, for callers that
  /// decide free-vs-paid themselves instead of going through [prepareUpload].
  int getMaxFreeItemBytes() => _uploadPaymentEvaluator.maxFreeItemBytes;

  Future<UploadPreparation> prepareUpload({
    required UploadParams params,
  }) async {
    final uploadPreparation = await _uploadPreparer.prepareFileUpload(params);

    final uploadPaymentInfo =
        await _uploadPaymentEvaluator.getUploadPaymentInfoForUploadPlans(
      uploadPlanForAR: uploadPreparation.uploadPlanForAr,
      uploadPlanForTurbo: uploadPreparation.uploadPlanForTurbo,
    );

    return UploadPreparation(
      uploadPlansPreparation: uploadPreparation,
      uploadPaymentInfo: uploadPaymentInfo,
    );
  }

  Future<UploadPaymentInfo> getUploadPaymentInfoForEntityUpload({
    required DataItem dataItem,
  }) async {
    final uploadPaymentInfo =
        await _uploadPaymentEvaluator.getUploadPaymentInfoForEntities(
      dataItem: dataItem,
    );

    return uploadPaymentInfo;
  }
}

class UploadParams {
  final User user;
  final List<UploadFile> files;
  final FolderEntry targetFolder;
  final Drive targetDrive;
  final Map<String, String> conflictingFiles;
  final Map<String, WebFolder> foldersByPath;
  final bool containsSupportedImageTypeForThumbnailGeneration;
  final ARNSUndername? arnsUnderName;
  final List<String>? paidBy;

  UploadParams({
    required this.user,
    required this.files,
    required this.targetFolder,
    required this.targetDrive,
    required this.conflictingFiles,
    required this.foldersByPath,
    required this.containsSupportedImageTypeForThumbnailGeneration,
    this.paidBy,
    this.arnsUnderName,
  });

  UploadParams copyWith({
    ARNSUndername? arnsUnderName,
    List<String>? paidBy,
  }) {
    return UploadParams(
      user: user,
      files: files,
      targetFolder: targetFolder,
      targetDrive: targetDrive,
      conflictingFiles: conflictingFiles,
      foldersByPath: foldersByPath,
      containsSupportedImageTypeForThumbnailGeneration:
          containsSupportedImageTypeForThumbnailGeneration,
      arnsUnderName: arnsUnderName,
      paidBy: paidBy,
    );
  }
}
