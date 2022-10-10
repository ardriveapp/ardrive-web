import 'dart:convert';

import 'package:ardrive/blocs/upload/cost_estimate.dart';
import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/blocs/upload/models/upload_plan.dart';
import 'package:ardrive/blocs/upload/upload_handles/handles.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/pst/pst.dart';
import 'package:ardrive/types/winston.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart' show TestWidgetsFlutterBinding;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/fake_data.dart';
import '../test_utils/utils.dart';

const stubEntityId = '00000000-0000-0000-0000-000000000000';
const stubTxId = '0000000000000000000000000000000000000000001';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final driveDao = MockDriveDao();
  final pstService = MockPstService();
  final wallet = getTestWallet();
  final cipherKey = SecretKeyData.random(length: 32);
  const double winstonToArFactor = 1000000000000;
  const double stubByteCountToWinstonFactor = 2;
  const double stubArToUsdFactor = 3;
  const double stubPstFeeFactor = .15;

  group('CostEstimate class', () {
    final stubCurrentDate = DateTime.now();

    late MockArweaveService arweave;
    late Drive stubDrive;

    final stubRootFolderEntry = FolderEntry(
      id: stubEntityId,
      dateCreated: stubCurrentDate,
      driveId: stubEntityId,
      isGhost: false,
      parentFolderId: stubEntityId,
      path: '/root-folder',
      name: 'root-folder',
      lastUpdated: stubCurrentDate,
    );

    setUp(() async {
      arweave = MockArweaveService();

      stubDrive = Drive(
        id: stubEntityId,
        rootFolderId: stubEntityId,
        ownerAddress: await wallet.getAddress(),
        name: 'My awesome drive',
        privacy: DrivePrivacy.public,
        dateCreated: stubCurrentDate,
        lastUpdated: stubCurrentDate,
      );

      when(() => arweave.getPrice(byteSize: any(named: 'byteSize'))).thenAnswer(
        (invocation) => Future.value(
          BigInt.from(
            stubByteCountToWinstonFactor *
                invocation.namedArguments[const Symbol('byteSize')],
          ),
        ),
      );

      registerFallbackValue(BigInt.zero);
      when(() => arweave.getArUsdConversionRate()).thenAnswer(
        (_) => Future.value(stubArToUsdFactor),
      );

      when(() => pstService.getPSTFee(any())).thenAnswer(
        (invocation) => Future.value(
          Winston(
            (invocation.positionalArguments[0] as BigInt) *
                BigInt.from(stubPstFeeFactor * 100) ~/
                BigInt.from(100),
          ),
        ),
      );
    });

    group('constructor', () {
      final List<String> validPlatforms = ['Web', 'Android', 'iOS', 'unknown'];

      late List<IOFile> multipleFilesToUpload;
      late List<IOFile> singleFileToUpload;
      late UploadPlanUtils uploadPlanUtis;

      setUp(() async {
        multipleFilesToUpload = [
          await IOFile.fromData(
            Uint8List.fromList([1, 2, 3, 4]),
            name: 'File number one',
            lastModifiedDate: DateTime(2022),
          ),
          await IOFile.fromData(
            Uint8List.fromList([1, 2, 3, 4]),
            name: 'File number two',
            lastModifiedDate: DateTime(2022),
          )
        ];
        singleFileToUpload = [
          await IOFile.fromData(
            Uint8List(503316480),
            name: 'Single file entity',
            lastModifiedDate: DateTime(2022),
          ),
        ];
      });

      for (String stubPlatformString in validPlatforms) {
        test(
            'returns the expected values for Bundles on platform: "$stubPlatformString"',
            () async {
          uploadPlanUtis = UploadPlanUtils(
            arweave: arweave,
            driveDao: driveDao,
            platform: stubPlatformString,
            version: version,
          );

          final uploadFiles = multipleFilesToUpload
              .map(
                (ioFile) =>
                    UploadFile(ioFile: ioFile, parentFolderId: stubEntityId),
              )
              .toList();

          final uploadPlan = await uploadPlanUtis.filesToUploadPlan(
            files: uploadFiles,
            cipherKey: cipherKey,
            wallet: wallet,
            conflictingFiles: {},
            targetDrive: stubDrive,
            targetFolder: stubRootFolderEntry,
          );

          final estimate = await CostEstimate.create(
            uploadPlan: uploadPlan,
            arweaveService: arweave,
            pstService: pstService,
            wallet: wallet,
          );

          final BigInt expectedDataSize = await expectedCostForUploadPlan(
            uploadPlan: uploadPlan,
            pstService: pstService,
            arweaveService: arweave,
            platform: stubPlatformString,
          );

          expect(estimate.totalCost, expectedDataSize);
          expect(
            estimate.arUploadCost,
            winstonToAr(expectedDataSize),
          );
          final expectedPstFee = await pstService.getPSTFee(
            BigInt.from(
              // the total minus the 15% fee
              expectedDataSize.toInt() * 0.8695652173913044,
            ),
          );
          expect(
            estimate.pstFee,
            expectedPstFee.value,
          );
        });

        test(
            'returns the expected values for v2 on platform: "$stubPlatformString"',
            () async {
          uploadPlanUtis = UploadPlanUtils(
            arweave: arweave,
            driveDao: driveDao,
            platform: stubPlatformString,
            version: version,
          );

          final uploadFiles = singleFileToUpload
              .map(
                (ioFile) =>
                    UploadFile(ioFile: ioFile, parentFolderId: stubEntityId),
              )
              .toList();

          final uploadPlan = await uploadPlanUtis.filesToUploadPlan(
            files: uploadFiles,
            cipherKey: cipherKey,
            wallet: wallet,
            conflictingFiles: {},
            targetDrive: stubDrive,
            targetFolder: stubRootFolderEntry,
          );

          final estimate = await CostEstimate.create(
            uploadPlan: uploadPlan,
            arweaveService: arweave,
            pstService: pstService,
            wallet: wallet,
          );

          final BigInt expectedDataSize = await expectedCostForUploadPlan(
            uploadPlan: uploadPlan,
            pstService: pstService,
            arweaveService: arweave,
            platform: stubPlatformString,
          );

          expect(estimate.totalCost, expectedDataSize);
          expect(
            estimate.arUploadCost,
            winstonToAr(expectedDataSize),
          );
          final expectedPstFee = await pstService.getPSTFee(
            BigInt.from(
              // the total minus the 15% fee
              expectedDataSize.toInt() * 0.8695652173913044,
            ),
          );
          expect(
            estimate.pstFee,
            expectedPstFee.value,
          );
        });
      }
    });
  });
}

Future<BigInt> expectedCostForUploadPlan({
  required UploadPlan uploadPlan,
  required PstService pstService,
  required ArweaveService arweaveService,
  required String platform,
}) async {
  final dataItemsCost = await expectedCostForAllBundles(
    uploadPlan.bundleUploadHandles,
    arweaveService,
  );

  final v2FilesUploadCost = await expectedCostForV2Uploads(
    dataItemHandles: uploadPlan.fileV2UploadHandles.values.toList(),
    platform: platform,
    arweave: arweaveService,
  );

  final bundlePstFee = await pstService.getPSTFee(dataItemsCost);
  final v2FilesPstFee = await pstService.getPSTFee(v2FilesUploadCost);

  return dataItemsCost +
      bundlePstFee.value +
      v2FilesUploadCost +
      v2FilesPstFee.value;
}

Future<BigInt> expectedCostForAllBundles(
  List<BundleUploadHandle> bundleUploadHandles,
  ArweaveService arweave,
) async {
  var totalCost = BigInt.zero;
  for (var bundle in bundleUploadHandles) {
    totalCost += await expectedCostForSingleBundle(
      bundleUploadHandle: bundle,
      arweave: arweave,
    );
  }
  return totalCost;
}

Future<BigInt> expectedCostForSingleBundle({
  required BundleUploadHandle bundleUploadHandle,
  required ArweaveService arweave,
}) {
  return arweave.getPrice(byteSize: bundleUploadHandle.computeBundleSize());
}

Future<BigInt> expectedCostForV2Uploads({
  required List<FileV2UploadHandle> dataItemHandles,
  required ArweaveService arweave,
  required String platform,
}) async {
  BigInt totalCost = BigInt.zero;
  for (FileV2UploadHandle handle in dataItemHandles) {
    totalCost += await expectedSizeForV2Item(
      v2FileHandle: handle,
      arweave: arweave,
    );
  }
  return totalCost;
}

Future<BigInt> expectedSizeForV2Item({
  required FileV2UploadHandle v2FileHandle,
  required ArweaveService arweave,
}) async {
  return await arweave.getPrice(byteSize: v2FileHandle.getFileDataSize()) +
      await arweave.getPrice(byteSize: v2FileHandle.getMetadataJSONSize());
}

int expectedCostForJSONData(FileEntity entity) {
  final entityFake = FileEntity(
    id: entity.id,
    dataContentType: entity.dataContentType,
    dataTxId: base64Encode(Uint8List(43)),
    driveId: entity.driveId,
    lastModifiedDate: entity.lastModifiedDate,
    name: entity.name,
    parentFolderId: entity.parentFolderId,
    size: entity.size,
  );
  return (utf8.encode(json.encode(entityFake)) as Uint8List).lengthInBytes;
}
