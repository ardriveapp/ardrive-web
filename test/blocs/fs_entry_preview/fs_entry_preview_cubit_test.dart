import 'dart:typed_data';

import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Selectable;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

class MockDataGatewayFallback extends Mock implements DataGatewayFallback {}

class MockDrive extends Mock implements Drive {}

class MockSelectable<T> extends Mock implements Selectable<T> {}

/// Mimics [DataGatewayFallback]'s serial waterfall: every entry of [gateways]
/// is tried in order and the first one that does not throw wins.
///
/// Used to prove the preview path survives a dead primary gateway without
/// reaching for the network in a unit test.
class WaterfallGatewayFallback extends Mock implements DataGatewayFallback {
  WaterfallGatewayFallback(this.gateways);

  final List<Future<http.Response> Function()> gateways;
  final List<int> attemptedGateways = [];

  @override
  Future<http.Response> fetchData(String txId, Arweave primaryClient) async {
    Object? lastError;

    for (var i = 0; i < gateways.length; i++) {
      attemptedGateways.add(i);

      try {
        return await gateways[i]();
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception('All gateways failed for tx $txId: $lastError');
  }
}

const driveId = 'drive-id';
const fileId = 'file-id';
const dataTxId = 'data-tx-id';
const gatewayUrl = 'https://gateway.example';

const previewMaxFileSize = 1024 * 1024 * 100;
const overLimitFileSize = previewMaxFileSize + 1;
const underLimitFileSize = 1024 * 1024;

FileDataTableItem createImageItem({required int size}) => FileDataTableItem(
      driveId: driveId,
      lastUpdated: DateTime(2024),
      name: 'photo.png',
      size: size,
      dateCreated: DateTime(2024),
      contentType: 'image/png',
      index: 0,
      isOwner: true,
      fileId: fileId,
      parentFolderId: 'parent-folder-id',
      dataTxId: dataTxId,
      lastModifiedDate: DateTime(2024),
      metadataTx: null,
      dataTx: null,
      pinnedDataOwnerAddress: null,
    );

void main() {
  late MockDriveDao mockDriveDao;
  late MockConfigService mockConfigService;
  late MockArweaveService mockArweaveService;
  late MockProfileCubit mockProfileCubit;
  late MockArDriveCrypto mockCrypto;
  late MockArweave mockArweaveClient;
  late MockDataGatewayFallback mockGatewayFallback;

  setUpAll(() {
    registerFallbackValue(MockArweave());
    registerFallbackValue(MockTransactionCommonMixin());
    registerFallbackValue(SecretKey([]));
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    mockDriveDao = MockDriveDao();
    mockConfigService = MockConfigService();
    mockArweaveService = MockArweaveService();
    mockProfileCubit = MockProfileCubit();
    mockCrypto = MockArDriveCrypto();
    mockArweaveClient = MockArweave();
    mockGatewayFallback = MockDataGatewayFallback();

    FsEntryPreviewCubit.imagePreviewNotifier.value = null;

    when(() => mockConfigService.config).thenReturn(
      AppConfig(
        allowedDataItemSizeForTurbo: 1,
        stripePublishableKey: 'stripePublishableKey',
        arweaveGatewayForDataRequest: const SelectedGateway(
          label: 'Gateway',
          url: gatewayUrl,
        ),
      ),
    );

    when(() => mockArweaveService.client).thenReturn(mockArweaveClient);
    when(() => mockArweaveService.gatewayFallback)
        .thenReturn(mockGatewayFallback);
    when(
      () => mockDriveDao.putPreviewDataInMemory(
        dataTxId: any(named: 'dataTxId'),
        bytes: any(named: 'bytes'),
      ),
    ).thenAnswer((_) async {});
    when(() => mockDriveDao.getPreviewDataFromMemory(any()))
        .thenAnswer((_) async => null);
  });

  FsEntryPreviewCubit buildSharedFileCubit({
    required FileDataTableItem item,
    SecretKey? fileKey,
    DataGatewayFallback? gatewayFallback,
  }) {
    if (gatewayFallback != null) {
      when(() => mockArweaveService.gatewayFallback)
          .thenReturn(gatewayFallback);
    }

    return FsEntryPreviewCubit(
      driveId: driveId,
      maybeSelectedItem: item,
      driveDao: mockDriveDao,
      configService: mockConfigService,
      arweave: mockArweaveService,
      profileCubit: mockProfileCubit,
      crypto: mockCrypto,
      fileKey: fileKey,
      isSharedFile: true,
    );
  }

  void expectNoBytesFetched() {
    verifyNever(() => mockArweaveService.gatewayFallback);
    verifyNever(() => mockGatewayFallback.fetchData(any(), any()));
    verifyNever(
      () => mockGatewayFallback.fetchManifestWithFallback(any(), any()),
    );
    verifyNever(
      () => mockDriveDao.putPreviewDataInMemory(
        dataTxId: any(named: 'dataTxId'),
        bytes: any(named: 'bytes'),
      ),
    );
  }

  group('FsEntryPreviewCubit image size cap (F10)', () {
    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'over-limit private image emits oversized and never fetches the bytes',
      build: () => buildSharedFileCubit(
        item: createImageItem(size: overLimitFileSize),
        fileKey: SecretKey([1, 2, 3]),
      ),
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        expect(cubit.state, isA<FsEntryPreviewOversized>());
        expect(
          (cubit.state as FsEntryPreviewOversized).fileSize,
          overLimitFileSize,
        );
        expect(
          (cubit.state as FsEntryPreviewOversized).maxFileSize,
          previewMaxFileSize,
        );

        // The whole point of the fix: no bytes are requested, and nothing is
        // decrypted, for an over-limit private image.
        expectNoBytesFetched();
        verifyNever(
          () => mockCrypto.decryptDataFromTransaction(any(), any(), any()),
        );

        expect(FsEntryPreviewCubit.imagePreviewNotifier.value, isNull);
      },
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'over-limit public image emits oversized and never fetches the bytes',
      build: () => buildSharedFileCubit(
        item: createImageItem(size: overLimitFileSize),
      ),
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        expect(cubit.state, isA<FsEntryPreviewOversized>());
        expectNoBytesFetched();
        expect(FsEntryPreviewCubit.imagePreviewNotifier.value, isNull);
      },
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'over-limit public image in the drive explorer emits oversized',
      build: () {
        final drive = MockDrive();
        final driveSelectable = MockSelectable<Drive>();
        final fileSelectable = MockSelectable<FileEntry>();

        when(() => drive.privacy).thenReturn(DrivePrivacyTag.public);
        when(() => mockDriveDao.driveById(driveId: driveId))
            .thenReturn(driveSelectable);
        when(() => driveSelectable.getSingleOrNull())
            .thenAnswer((_) async => drive);
        when(() => driveSelectable.getSingle()).thenAnswer((_) async => drive);
        when(() => mockDriveDao.fileById(fileId: fileId))
            .thenReturn(fileSelectable);
        when(() => fileSelectable.watchSingle())
            .thenAnswer((_) => const Stream<FileEntry>.empty());

        return FsEntryPreviewCubit(
          driveId: driveId,
          maybeSelectedItem: createImageItem(size: overLimitFileSize),
          driveDao: mockDriveDao,
          configService: mockConfigService,
          arweave: mockArweaveService,
          profileCubit: mockProfileCubit,
          crypto: mockCrypto,
        );
      },
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        expect(cubit.state, isA<FsEntryPreviewOversized>());
        expectNoBytesFetched();
      },
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'under-limit public image is still previewed',
      build: () {
        when(() => mockGatewayFallback.fetchData(any(), any())).thenAnswer(
          (_) async => http.Response.bytes(<int>[1, 2, 3, 4], 200),
        );

        return buildSharedFileCubit(
          item: createImageItem(size: underLimitFileSize),
        );
      },
      wait: const Duration(milliseconds: 100),
      expect: () => [
        const FsEntryPreviewImage(previewUrl: '$gatewayUrl/$dataTxId'),
      ],
      verify: (cubit) {
        verify(() => mockGatewayFallback.fetchData(dataTxId, any())).called(1);
        expect(
          FsEntryPreviewCubit.imagePreviewNotifier.value?.dataBytes,
          Uint8List.fromList([1, 2, 3, 4]),
        );
      },
    );
  });

  group('FsEntryPreviewCubit gateway fallback (F7)', () {
    late WaterfallGatewayFallback waterfallGatewayFallback;

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'previews the file when the primary gateway fails and a fallback succeeds',
      build: () {
        waterfallGatewayFallback = WaterfallGatewayFallback([
          () => throw Exception('primary gateway is blackholed'),
          () async => http.Response.bytes(<int>[9, 8, 7], 200),
        ]);

        return buildSharedFileCubit(
          item: createImageItem(size: underLimitFileSize),
          gatewayFallback: waterfallGatewayFallback,
        );
      },
      wait: const Duration(milliseconds: 100),
      expect: () => [
        const FsEntryPreviewImage(previewUrl: '$gatewayUrl/$dataTxId'),
      ],
      verify: (cubit) {
        expect(waterfallGatewayFallback.attemptedGateways, [0, 1]);
        expect(
          FsEntryPreviewCubit.imagePreviewNotifier.value?.dataBytes,
          Uint8List.fromList([9, 8, 7]),
        );
      },
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'emits unavailable when every gateway fails',
      build: () {
        waterfallGatewayFallback = WaterfallGatewayFallback([
          () => throw Exception('primary gateway is blackholed'),
          () => throw Exception('fallback gateway is blackholed'),
        ]);

        return buildSharedFileCubit(
          item: createImageItem(size: underLimitFileSize),
          gatewayFallback: waterfallGatewayFallback,
        );
      },
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        expect(waterfallGatewayFallback.attemptedGateways, [0, 1]);
        expect(cubit.state, isA<FsEntryPreviewUnavailable>());
        expect(cubit.state, isNot(isA<FsEntryPreviewOversized>()));
      },
    );
  });
}
