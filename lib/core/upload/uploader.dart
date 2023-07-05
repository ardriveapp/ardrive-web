import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/blocs/upload/models/upload_plan.dart';
import 'package:ardrive/blocs/upload/models/web_folder.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/blocs/upload/upload_handles/handles.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/services/turbo/upload_service.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/size_utils.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:tuple/tuple.dart';

class ArDriveUploader {
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

  ArDriveUploader({
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
  }) async* {
    final List<double> progresses = List.filled(
      bundleHandles.length + fileV2Handles.length,
      0.0,
    );

    int index = 0;

    for (final bundleHandle in bundleHandles) {
      await for (var progress in _uploadItem(
        index: index++,
        itemHandle: bundleHandle,
        prepare: _prepareBundle,
        upload: _bundleUploader.upload,
        onFinishUpload: _onFinishBundleUpload,
        onUploadError: _onUploadBundleError,
        dispose: (handle) =>
            handle.clearBundleData(useTurbo: _bundleUploader.useTurbo),
      )) {
        progresses[progress.item1] = progress.item2;
        yield progresses.reduce((a, b) => a + b) / progresses.length;
      }
    }

    for (final fileV2Handle in fileV2Handles) {
      await for (var progress in _uploadItem(
        index: index++,
        itemHandle: fileV2Handle,
        prepare: _prepareFile,
        upload: _fileV2Uploader.upload,
        onFinishUpload: _onFinishFileUpload,
        onUploadError: _onUploadFileError,
        dispose: (handle) => handle.dispose(),
      )) {
        progresses[progress.item1] = progress.item2;
        yield progresses.reduce((a, b) => a + b) / progresses.length;
      }
    }
  }

  Stream<Tuple2<int, double>> _uploadItem<T>({
    required T itemHandle,
    required int index,
    required Future<void> Function(T handle) prepare,
    required Stream<double> Function(T handle) upload,
    required Future<void> Function(T handle) onFinishUpload,
    required Future<void> Function(T handle, Object error) onUploadError,
    required void Function(T handle) dispose,
  }) async* {
    try {
      final itemString = itemHandle.toString();

      logger.i('Preparing $itemString');

      await prepare(itemHandle);

      bool hasError = false;

      await for (var progress in upload(itemHandle).handleError((e, s) {
        logger.e('Handling error on ArDriveUploader with $itemString', e, s);
        hasError = true;
      })) {
        yield Tuple2(index, progress);
      }

      if (hasError) {
        logger.d(
            'Error in ${itemString.toString()} upload, breaking upload for $itemString');
        logger.i('Disposing ${itemString.toString()}');

        dispose(itemHandle);

        throw Exception();
      }

      logger.i('Finished uploading $itemString');
      logger.i('Disposing $itemString');

      onFinishUpload(itemHandle).then((value) => dispose(itemHandle));
    } catch (e, stacktrace) {
      logger.e('Error in ${itemHandle.toString()} upload', e, stacktrace);
      onUploadError(itemHandle, e);
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
      logger.i('Using ArweaveBunldeUploader');

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
    yield 0;
    handle.setUploadProgress(0);
    await _turbo
        .postDataItem(dataItem: handle.bundleDataItem, wallet: _wallet)
        .onError((error, stackTrace) {
      logger.e(error);
      throw Exception();
    });
    handle.setUploadProgress(1);
    yield 1;
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

  FileV2Uploader(this._arweave);

  @override
  Stream<double> upload(handle) async* {
    yield* _arweave.transactions
        .upload(handle.entityTx, maxConcurrentUploadCount: 1)
        .map((upload) {
      return upload.progress;
    });
  }
}

class UploadPreparer {
  final UploadPlanUtils _uploadPlanUtils;

  UploadPreparer({
    required UploadPlanUtils uploadPlanUtils,
  }) : _uploadPlanUtils = uploadPlanUtils;

  Future<UploadPlansPreparation> prepareUpload(UploadParams params) async {
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

  UploadPaymentEvaluator({
    required TurboBalanceRetriever turboBalanceRetriever,
    required UploadCostEstimateCalculatorForAR
        uploadCostEstimateCalculatorForAR,
    required ArDriveAuth auth,
    required TurboUploadCostCalculator turboUploadCostCalculator,
    required AppConfig appConfig,
  })  : _turboBalanceRetriever = turboBalanceRetriever,
        _appConfig = appConfig,
        _uploadCostEstimateCalculatorForAR = uploadCostEstimateCalculatorForAR,
        _auth = auth,
        _turboUploadCostCalculator = turboUploadCostCalculator;

  Future<UploadPaymentInfo> getUploadPaymentInfo({
    required UploadPlan uploadPlanForAR,
    required UploadPlan uploadPlanForTurbo,
  }) async {
    UploadMethod uploadMethod;

    int totalSize = 0;

    final turboEligibility = await _getTurboAvailability(
      uploadPlanForTurbo: uploadPlanForTurbo,
      uploadPlanForAR: uploadPlanForAR,
    );

    final arSize = await _getARSize(uploadPlanForAR);

    /// Calculate the upload with AR is not optional
    final arCostEstimate =
        await _uploadCostEstimateCalculatorForAR.calculateCost(
      totalSize: arSize,
    );

    uploadMethod = _determineUploadMethod(
      turboEligibility: turboEligibility,
      arCostEstimate: arCostEstimate,
      arSize: arSize,
    );

    if (uploadMethod == UploadMethod.turbo) {
      totalSize = turboEligibility.turboBundleSizes;
    } else {
      totalSize = arSize;
    }

    return UploadPaymentInfo(
      defaultPaymentMethod: uploadMethod,
      arCostEstimate: arCostEstimate,
      turboCostEstimate: turboEligibility.turboCostEstimate,
      totalSize: totalSize,
      turboBalance: turboEligibility.turboBalance,
      turboEligibility: turboEligibility,
    );
  }

  Future<TurboAvailability> _getTurboAvailability({
    required UploadPlan uploadPlanForAR,
    required UploadPlan uploadPlanForTurbo,
  }) async {
    late BigInt turboBalance;

    bool isTurboAvailable = _appConfig.useTurboUpload;

    if (isTurboAvailable) {
      /// Check the balance of the user
      /// If we can't get the balance, turbo won't be available
      try {
        turboBalance =
            await _turboBalanceRetriever.getBalance(_auth.currentUser!.wallet);
      } catch (e) {
        logger.e(e);
        isTurboAvailable = false;
        turboBalance = BigInt.zero;
      }
    } else {
      turboBalance = BigInt.zero;
    }

    bool isUploadEligibleToTurbo =
        uploadPlanForAR.fileV2UploadHandles.isEmpty &&
            uploadPlanForTurbo.bundleUploadHandles.isNotEmpty;

    UploadCostEstimate turboCostEstimate = UploadCostEstimate.zero();

    int turboBundleSizes = 0;

    /// Calculate the upload with Turbo if possible
    if (isTurboAvailable && isUploadEligibleToTurbo) {
      turboBundleSizes = await sizeUtils
          .getSizeOfAllBundles(uploadPlanForTurbo.bundleUploadHandles);

      try {
        turboCostEstimate = await _turboUploadCostCalculator.calculateCost(
          totalSize: turboBundleSizes,
        );
      } catch (e) {
        isTurboAvailable = false;
      }
    }

    bool isFreeUploadPossibleUsingTurbo = false;

    if (isTurboAvailable && isUploadEligibleToTurbo) {
      final allowedDataItemSizeForTurbo =
          _appConfig.allowedDataItemSizeForTurbo;

      isFreeUploadPossibleUsingTurbo =
          uploadPlanForTurbo.bundleUploadHandles.every(
        (bundle) => bundle.fileDataItemUploadHandles.every(
          (file) => file.size <= allowedDataItemSizeForTurbo,
        ),
      );
    }

    return TurboAvailability(
      isTurboAvailable: isTurboAvailable,
      turboBalance: turboBalance,
      isUploadEligibleToTurbo: isUploadEligibleToTurbo,
      turboCostEstimate: turboCostEstimate,
      turboBundleSizes: turboBundleSizes,
      isFreeUploadPossibleUsingTurbo: isFreeUploadPossibleUsingTurbo,
    );
  }

  Future<int> _getARSize(UploadPlan uploadPlan) async {
    final arBundleSizes =
        await sizeUtils.getSizeOfAllBundles(uploadPlan.bundleUploadHandles);
    final arFileSizes =
        await sizeUtils.getSizeOfAllV2Files(uploadPlan.fileV2UploadHandles);

    return arBundleSizes + arFileSizes;
  }

  UploadMethod _determineUploadMethod({
    required TurboAvailability turboEligibility,
    required UploadCostEstimate arCostEstimate,
    required int arSize,
  }) {
    if (turboEligibility.isTurboAvailable &&
        turboEligibility.isUploadEligibleToTurbo &&
        turboEligibility.turboBalance >=
            turboEligibility.turboCostEstimate.totalCost) {
      return UploadMethod.turbo;
    } else {
      return UploadMethod.ar;
    }
  }
}

class TurboAvailability {
  final bool isTurboAvailable;
  final bool isUploadEligibleToTurbo;
  final bool isFreeUploadPossibleUsingTurbo;
  final BigInt turboBalance;
  final UploadCostEstimate turboCostEstimate;
  final int turboBundleSizes;

  TurboAvailability({
    required this.isTurboAvailable,
    required this.turboBalance,
    required this.isUploadEligibleToTurbo,
    required this.turboCostEstimate,
    required this.turboBundleSizes,
    required this.isFreeUploadPossibleUsingTurbo,
  });
}

class _CostEstimates {
  final UploadCostEstimate arCostEstimate;
  final UploadCostEstimate turboCostEstimate;

  _CostEstimates({
    required this.arCostEstimate,
    required this.turboCostEstimate,
  });
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
  final TurboAvailability turboEligibility;
  final UploadCostEstimate arCostEstimate;
  final UploadCostEstimate turboCostEstimate;
  final int totalSize;
  final BigInt turboBalance;

  UploadPaymentInfo({
    required this.defaultPaymentMethod,
    required this.arCostEstimate,
    required this.turboCostEstimate,
    required this.totalSize,
    required this.turboBalance,
    required this.turboEligibility,
  });
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

  Future<UploadPreparation> prepareUpload({
    required UploadParams params,
  }) async {
    final uploadPreparation = await _uploadPreparer.prepareUpload(params);

    final uploadPaymentInfo =
        await _uploadPaymentEvaluator.getUploadPaymentInfo(
      uploadPlanForAR: uploadPreparation.uploadPlanForAr,
      uploadPlanForTurbo: uploadPreparation.uploadPlanForTurbo,
    );

    return UploadPreparation(
      uploadPlansPreparation: uploadPreparation,
      uploadPaymentInfo: uploadPaymentInfo,
    );
  }
}

class UploadParams {
  final User user;
  final List<UploadFile> files;
  final FolderEntry targetFolder;
  final Drive targetDrive;
  final Map<String, String> conflictingFiles;
  final Map<String, WebFolder> foldersByPath;

  UploadParams({
    required this.user,
    required this.files,
    required this.targetFolder,
    required this.targetDrive,
    required this.conflictingFiles,
    required this.foldersByPath,
  });
}
