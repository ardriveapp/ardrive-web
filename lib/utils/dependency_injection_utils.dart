import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/core/arfs/repository/file_metadata_repository.dart';
import 'package:ardrive/core/arfs/use_cases/bulk_import_files.dart';
import 'package:ardrive/core/arfs/use_cases/get_file_metadata.dart';
import 'package:ardrive/core/arfs/use_cases/insert_file_metadata.dart';
import 'package:ardrive/core/arfs/use_cases/upload_file_metadata.dart';
import 'package:ardrive/core/arfs/use_cases/upload_folder_metadata.dart';
import 'package:ardrive/core/arfs/use_cases/verify_parent_folder.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/core/upload/domain/repository/upload_repository.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/services/license/license_service.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pst/pst.dart';

TurboBalanceRetriever _turboBalanceRetriever(BuildContext context) {
  return TurboBalanceRetriever(paymentService: context.read<PaymentService>());
}

TurboUploadCostCalculator _turboUploadCostCalculator(BuildContext context) {
  return TurboUploadCostCalculator(
    priceEstimator: TurboPriceEstimator(
      wallet: context.read<ArDriveAuth>().currentUser.wallet,
      costCalculator: TurboCostCalculator(
        paymentService: context.read<PaymentService>(),
      ),
      paymentService: context.read<PaymentService>(),
    ),
    turboCostCalculator: TurboCostCalculator(
      paymentService: context.read<PaymentService>(),
    ),
  );
}

UploadCostEstimateCalculatorForAR _uploadCostEstimateCalculatorForAR(
    BuildContext context) {
  return UploadCostEstimateCalculatorForAR(
    arweaveService: context.read<ArweaveService>(),
    pstService: context.read<PstService>(),
    arCostToUsd: ConvertArToUSD(
      arweave: context.read<ArweaveService>(),
    ),
  );
}

UploadPreparer _uploadPreparer(BuildContext context) {
  return UploadPreparer(
    uploadPlanUtils: UploadPlanUtils(
      crypto: ArDriveCrypto(),
      arweave: context.read<ArweaveService>(),
      turboUploadService: context.read<TurboUploadService>(),
      driveDao: context.read<DriveDao>(),
    ),
  );
}

UploadPaymentEvaluator _uploadPaymentEvaluator(BuildContext context) {
  return UploadPaymentEvaluator(
    appConfig: context.read<ConfigService>().config,
    auth: context.read<ArDriveAuth>(),
    turboBalanceRetriever: _turboBalanceRetriever(context),
    turboUploadCostCalculator: _turboUploadCostCalculator(context),
    uploadCostEstimateCalculatorForAR:
        _uploadCostEstimateCalculatorForAR(context),
  );
}

ArDriveUploadPreparationManager createArDriveUploadPreparationManager(
    BuildContext context) {
  return ArDriveUploadPreparationManager(
    uploadPreparePaymentOptions: _uploadPaymentEvaluator(context),
    uploadPreparer: _uploadPreparer(context),
  );
}

UploadRepository createUploadRepository(BuildContext context) {
  return UploadRepository(
    ardriveIO: ArDriveIO(),
    ardriveUploader: ArDriveUploader(
      turboUploadUri: Uri.parse(
          context.read<ConfigService>().config.defaultTurboUploadUrl!),
      metadataGenerator: ARFSUploadMetadataGenerator(
        tagsGenerator: ARFSTagsGenetator(
          appInfoServices: AppInfoServices(),
        ),
      ),
      arweave: Arweave(
        gatewayUrl: Uri.parse(
            context.read<ConfigService>().config.defaultArweaveGatewayUrl!),
      ),
      pstService: context.read<PstService>(),
    ),
    driveDao: context.read<DriveDao>(),
    auth: context.read<ArDriveAuth>(),
    licenseService: context.read<LicenseService>(),
  );
}

GetFileMetadata createGetFileMetadata(BuildContext context) {
  return GetFileMetadata(context.read<FileMetadataRepository>());
}

VerifyParentFolder createVerifyParentFolder(BuildContext context) {
  return VerifyParentFolder(context.read<DriveDao>());
}

InsertFileMetadata createInsertFileMetadata(BuildContext context) {
  return InsertFileMetadata(context.read<DriveDao>());
}

UploadFolderMetadata createUploadFolderMetadata(BuildContext context) {
  return UploadFolderMetadata(
    arweaveService: context.read<ArweaveService>(),
    turboUploadService: context.read<TurboUploadService>(),
  );
}

BulkImportFiles createBulkImportFiles(BuildContext context) {
  return BulkImportFiles(
    driveDao: context.read<DriveDao>(),
    arweaveService: context.read<ArweaveService>(),
    uploadFileMetadata: createUploadFileMetadata(context),
    uploadFolderMetadata: createUploadFolderMetadata(context),
    arDriveAuth: context.read<ArDriveAuth>(),
  );
}

UploadFileMetadata createUploadFileMetadata(BuildContext context) {
  return UploadFileMetadata(
    arweaveService: context.read<ArweaveService>(),
    turboUploadService: context.read<TurboUploadService>(),
  );
}
