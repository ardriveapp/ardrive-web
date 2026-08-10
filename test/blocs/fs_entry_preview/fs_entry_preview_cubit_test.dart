import 'dart:typed_data';

import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/utils/preview_object_urls.dart';
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

/// A [PreviewObjectUrls] that hands out a URL without a browser behind it.
///
/// The real one only works on the web, so the private media path could not be
/// exercised in a VM test at all without this seam.
class FakePreviewObjectUrls extends PreviewObjectUrls {
  final List<String> created = [];

  /// What each URL was made *out of*.
  ///
  /// The real one hands these bytes to a `<video>`; a fake that drops them on
  /// the floor cannot tell plaintext from ciphertext, and "one URL was created"
  /// is true either way.
  final List<Uint8List> createdBytes = [];

  final List<String> revoked = [];

  @override
  String? create(Uint8List bytes, String contentType) {
    final url = 'blob:fake/${created.length}-$contentType';
    created.add(url);
    createdBytes.add(bytes);

    return url;
  }

  @override
  void revoke(String url) => revoked.add(url);
}

/// A [PreviewObjectUrls] for a platform that has no in-memory media URL to
/// give - every non-web build.
class UnsupportedPreviewObjectUrls extends PreviewObjectUrls {
  @override
  String? create(Uint8List bytes, String contentType) => null;

  @override
  void revoke(String url) {}
}

const driveId = 'drive-id';
const fileId = 'file-id';
const dataTxId = 'data-tx-id';
const gatewayUrl = 'https://gateway.example';

const previewMaxFileSize = 1024 * 1024 * 100;
const overLimitFileSize = previewMaxFileSize + 1;
const underLimitFileSize = 1024 * 1024;

FileDataTableItem createItem({
  required int size,
  required String name,
  required String contentType,
}) =>
    FileDataTableItem(
      driveId: driveId,
      lastUpdated: DateTime(2024),
      name: name,
      size: size,
      dateCreated: DateTime(2024),
      contentType: contentType,
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

FileDataTableItem createImageItem({required int size}) => createItem(
      size: size,
      name: 'photo.png',
      contentType: 'image/png',
    );

FileDataTableItem createVideoItem({required int size}) => createItem(
      size: size,
      name: 'clip.mp4',
      contentType: 'video/mp4',
    );

FileDataTableItem createAudioItem({required int size}) => createItem(
      size: size,
      name: 'memo.mp3',
      contentType: 'audio/mpeg',
    );

FileDataTableItem createPdfItem({required int size}) => createItem(
      size: size,
      name: 'Q3 Report.pdf',
      contentType: 'application/pdf',
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
    PreviewObjectUrls? objectUrls,
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
      objectUrls: objectUrls,
    );
  }

  /// Makes the whole private path work: bytes from the gateway, cipher tags
  /// from the transaction, plaintext from the crypto.
  void stubPrivateFetchAndDecrypt({
    List<int> fetched = const [1, 2, 3, 4],
    List<int> decrypted = const [5, 6, 7, 8],
  }) {
    when(() => mockGatewayFallback.fetchData(any(), any())).thenAnswer(
      (_) async => http.Response.bytes(fetched, 200),
    );
    when(() => mockArweaveService.getTransactionDetails(any()))
        .thenAnswer((_) async => MockTransactionCommonMixin());
    when(() => mockCrypto.decryptDataFromTransaction(any(), any(), any()))
        .thenAnswer((_) async => Uint8List.fromList(decrypted));
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

  group('FsEntryPreviewCubit private media (F8)', () {
    late FakePreviewObjectUrls objectUrls;

    setUp(() => objectUrls = FakePreviewObjectUrls());

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'under-limit private video is fetched, decrypted and played from memory',
      build: () {
        stubPrivateFetchAndDecrypt();

        return buildSharedFileCubit(
          item: createVideoItem(size: underLimitFileSize),
          fileKey: SecretKey([1, 2, 3]),
          objectUrls: objectUrls,
        );
      },
      wait: const Duration(milliseconds: 100),
      expect: () => [
        const FsEntryPreviewLoading(),
        const FsEntryPreviewVideo(
          previewUrl: 'blob:fake/0-video/mp4',
          filename: 'clip.mp4',
        ),
      ],
      verify: (cubit) {
        verify(() => mockGatewayFallback.fetchData(dataTxId, any())).called(1);
        verify(
          () => mockCrypto.decryptDataFromTransaction(any(), any(), any()),
        ).called(1);

        // The player is given the *decrypted* bytes, never the ciphertext.
        // Passing the fetched bytes here instead would hand `<video>` the
        // encrypted blob, and the count would not move.
        expect(objectUrls.created, hasLength(1));
        expect(
          objectUrls.createdBytes.single,
          Uint8List.fromList([5, 6, 7, 8]),
        );
        expect(
          objectUrls.createdBytes.single,
          isNot(Uint8List.fromList([1, 2, 3, 4])),
        );
      },
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'under-limit private audio is fetched, decrypted and played from memory',
      build: () {
        stubPrivateFetchAndDecrypt();

        return buildSharedFileCubit(
          item: createAudioItem(size: underLimitFileSize),
          fileKey: SecretKey([1, 2, 3]),
          objectUrls: objectUrls,
        );
      },
      wait: const Duration(milliseconds: 100),
      expect: () => [
        const FsEntryPreviewLoading(),
        const FsEntryPreviewAudio(
          previewUrl: 'blob:fake/0-audio/mpeg',
          filename: 'memo.mp3',
        ),
      ],
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'over-limit private video emits oversized and never fetches the bytes',
      build: () => buildSharedFileCubit(
        item: createVideoItem(size: overLimitFileSize),
        fileKey: SecretKey([1, 2, 3]),
        objectUrls: objectUrls,
      ),
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        expect(cubit.state, isA<FsEntryPreviewOversized>());
        expectNoBytesFetched();
        verifyNever(
          () => mockCrypto.decryptDataFromTransaction(any(), any(), any()),
        );
      },
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'private video whose bytes cannot be played from memory is unavailable',
      build: () {
        stubPrivateFetchAndDecrypt();

        return buildSharedFileCubit(
          item: createVideoItem(size: underLimitFileSize),
          fileKey: SecretKey([1, 2, 3]),
          objectUrls: UnsupportedPreviewObjectUrls(),
        );
      },
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        expect(cubit.state, isA<FsEntryPreviewUnavailable>());
        expect(cubit.state, isNot(isA<FsEntryPreviewOversized>()));
      },
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'private video with no key is never fetched at all',
      build: () {
        final drive = MockDrive();
        final driveSelectable = MockSelectable<Drive>();
        final fileSelectable = MockSelectable<FileEntry>();

        when(() => drive.privacy).thenReturn(DrivePrivacyTag.private);
        when(() => mockDriveDao.driveById(driveId: driveId))
            .thenReturn(driveSelectable);
        when(() => driveSelectable.getSingleOrNull())
            .thenAnswer((_) async => drive);
        when(() => driveSelectable.getSingle()).thenAnswer((_) async => drive);
        when(() => mockDriveDao.fileById(fileId: fileId))
            .thenReturn(fileSelectable);
        when(() => fileSelectable.watchSingle())
            .thenAnswer((_) => const Stream<FileEntry>.empty());

        // No profile and no drive key in memory: there is no way to read this
        // file, so there is no reason to ask a gateway for it.
        when(() => mockProfileCubit.state).thenReturn(ProfileLoggingOut());
        when(() => mockDriveDao.getDriveKeyFromMemory(driveId))
            .thenAnswer((_) async => null);

        return FsEntryPreviewCubit(
          driveId: driveId,
          maybeSelectedItem: createVideoItem(size: underLimitFileSize),
          driveDao: mockDriveDao,
          configService: mockConfigService,
          arweave: mockArweaveService,
          profileCubit: mockProfileCubit,
          crypto: mockCrypto,
          objectUrls: objectUrls,
        );
      },
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        expect(cubit.state, isA<FsEntryPreviewUnavailable>());
        expectNoBytesFetched();
        verifyNever(
          () => mockCrypto.decryptDataFromTransaction(any(), any(), any()),
        );
        expect(objectUrls.created, isEmpty);
      },
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'private video survives a dead primary gateway',
      build: () {
        final waterfall = WaterfallGatewayFallback([
          () => throw Exception('primary gateway is blackholed'),
          () async => http.Response.bytes(<int>[9, 8, 7], 200),
        ]);

        when(() => mockArweaveService.getTransactionDetails(any()))
            .thenAnswer((_) async => MockTransactionCommonMixin());
        when(() => mockCrypto.decryptDataFromTransaction(any(), any(), any()))
            .thenAnswer((_) async => Uint8List.fromList([5, 6, 7, 8]));

        return buildSharedFileCubit(
          item: createVideoItem(size: underLimitFileSize),
          fileKey: SecretKey([1, 2, 3]),
          gatewayFallback: waterfall,
          objectUrls: objectUrls,
        );
      },
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        expect(cubit.state, isA<FsEntryPreviewVideo>());
        expect(
          (cubit.state as FsEntryPreviewVideo).previewUrl,
          'blob:fake/0-video/mp4',
        );
      },
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'public video still streams straight from the gateway',
      build: () => buildSharedFileCubit(
        item: createVideoItem(size: underLimitFileSize),
        objectUrls: objectUrls,
      ),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        const FsEntryPreviewVideo(
          previewUrl: '$gatewayUrl/$dataTxId',
          filename: 'clip.mp4',
        ),
      ],
      verify: (cubit) {
        expectNoBytesFetched();
        expect(objectUrls.created, isEmpty);
      },
    );

    test('the bytes behind a preview are released when the cubit closes',
        () async {
      stubPrivateFetchAndDecrypt();

      final cubit = buildSharedFileCubit(
        item: createVideoItem(size: underLimitFileSize),
        fileKey: SecretKey([1, 2, 3]),
        objectUrls: objectUrls,
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await cubit.close();

      expect(objectUrls.revoked, objectUrls.created);
    });
  });

  // A PDF is rasterised into page images and painted as Flutter widgets, so
  // its bytes are read into the app like an image's - and, for a private file,
  // decrypted here. What these tests hold down is where the bytes come from,
  // that they never come at all when they must not, and that a public file
  // still has the old open-in-a-new-tab escape hatch when they do not arrive.
  group('FsEntryPreviewCubit PDF (F9)', () {
    late FakePreviewObjectUrls objectUrls;
    late WaterfallGatewayFallback waterfallGatewayFallback;

    setUp(() => objectUrls = FakePreviewObjectUrls());

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'a public PDF survives a dead primary gateway',
      build: () {
        waterfallGatewayFallback = WaterfallGatewayFallback([
          () => throw Exception('primary gateway is blackholed'),
          () async => http.Response.bytes(<int>[9, 8, 7], 200),
        ]);

        return buildSharedFileCubit(
          item: createPdfItem(size: underLimitFileSize),
          gatewayFallback: waterfallGatewayFallback,
          objectUrls: objectUrls,
        );
      },
      wait: const Duration(milliseconds: 100),
      // Asserted through `verify` rather than `expect`, like every other test
      // here: the cubit starts resolving in its constructor, and the first
      // emission lands before `blocTest` has subscribed.
      verify: (cubit) {
        // The primary was tried and failed; the fallback served the bytes.
        expect(waterfallGatewayFallback.attemptedGateways, [0, 1]);

        expect(
          cubit.state,
          FsEntryPreviewPdf(
            previewUrl: '$gatewayUrl/$dataTxId',
            filename: 'Q3 Report.pdf',
            pdfBytes: Uint8List.fromList([9, 8, 7]),
            canOpenOnGateway: true,
          ),
        );

        // Nothing is decrypted for a public file, and nothing becomes a URL:
        // the bytes go to the rasteriser, in memory.
        verifyNever(
          () => mockCrypto.decryptDataFromTransaction(any(), any(), any()),
        );
        expect(objectUrls.created, isEmpty);
      },
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'a private PDF is fetched, decrypted and rendered from memory',
      build: () {
        stubPrivateFetchAndDecrypt();

        return buildSharedFileCubit(
          item: createPdfItem(size: underLimitFileSize),
          fileKey: SecretKey([1, 2, 3]),
          objectUrls: objectUrls,
        );
      },
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        expect(cubit.state, isA<FsEntryPreviewPdf>());

        final state = cubit.state as FsEntryPreviewPdf;

        // The rasteriser is handed the *plaintext*, never the ciphertext.
        expect(state.pdfBytes, Uint8List.fromList([5, 6, 7, 8]));

        // And a private file gets no gateway offer: every gateway holds only
        // its ciphertext.
        expect(state.canOpenOnGateway, isFalse);

        verify(() => mockGatewayFallback.fetchData(dataTxId, any())).called(1);
        verify(
          () => mockCrypto.decryptDataFromTransaction(any(), any(), any()),
        ).called(1);

        // No blob URL: the plaintext never leaves Dart memory.
        expect(objectUrls.created, isEmpty);
      },
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'a private PDF with no key is never fetched at all',
      build: () {
        final drive = MockDrive();
        final driveSelectable = MockSelectable<Drive>();
        final fileSelectable = MockSelectable<FileEntry>();

        when(() => drive.privacy).thenReturn(DrivePrivacyTag.private);
        when(() => mockDriveDao.driveById(driveId: driveId))
            .thenReturn(driveSelectable);
        when(() => driveSelectable.getSingleOrNull())
            .thenAnswer((_) async => drive);
        when(() => driveSelectable.getSingle()).thenAnswer((_) async => drive);
        when(() => mockDriveDao.fileById(fileId: fileId))
            .thenReturn(fileSelectable);
        when(() => fileSelectable.watchSingle())
            .thenAnswer((_) => const Stream<FileEntry>.empty());

        // No profile and no drive key in memory: there is no way to read this
        // file, so its ciphertext is not this page's to request.
        when(() => mockProfileCubit.state).thenReturn(ProfileLoggingOut());
        when(() => mockDriveDao.getDriveKeyFromMemory(driveId))
            .thenAnswer((_) async => null);

        return FsEntryPreviewCubit(
          driveId: driveId,
          maybeSelectedItem: createPdfItem(size: underLimitFileSize),
          driveDao: mockDriveDao,
          configService: mockConfigService,
          arweave: mockArweaveService,
          profileCubit: mockProfileCubit,
          crypto: mockCrypto,
          objectUrls: objectUrls,
        );
      },
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        expect(cubit.state, isA<FsEntryPreviewUnavailable>());
        expect(cubit.state, isNot(isA<FsEntryPreviewOversized>()));
        expectNoBytesFetched();
        verifyNever(
          () => mockCrypto.decryptDataFromTransaction(any(), any(), any()),
        );
      },
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'an over-limit private PDF emits oversized and never fetches the bytes',
      build: () => buildSharedFileCubit(
        item: createPdfItem(size: overLimitFileSize),
        fileKey: SecretKey([1, 2, 3]),
        objectUrls: objectUrls,
      ),
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        expect(cubit.state, isA<FsEntryPreviewOversized>());
        expect(
          (cubit.state as FsEntryPreviewOversized).maxFileSize,
          previewMaxFileSize,
        );
        expectNoBytesFetched();
        verifyNever(
          () => mockCrypto.decryptDataFromTransaction(any(), any(), any()),
        );
      },
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'an over-limit public PDF emits oversized and never fetches the bytes',
      build: () => buildSharedFileCubit(
        item: createPdfItem(size: overLimitFileSize),
        objectUrls: objectUrls,
      ),
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        expect(cubit.state, isA<FsEntryPreviewOversized>());
        expectNoBytesFetched();
      },
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'a public PDF whose bytes never arrive keeps the gateway affordance',
      build: () {
        final waterfall = WaterfallGatewayFallback([
          () => throw Exception('primary gateway is blackholed'),
          () => throw Exception('fallback gateway is blackholed'),
        ]);

        return buildSharedFileCubit(
          item: createPdfItem(size: underLimitFileSize),
          gatewayFallback: waterfall,
        );
      },
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        // Nothing to rasterise, but the file's own gateway URL is still there
        // to be opened in a new tab - which is all this path could ever do
        // before it rendered anything.
        expect(
          cubit.state,
          const FsEntryPreviewPdf(
            previewUrl: '$gatewayUrl/$dataTxId',
            filename: 'Q3 Report.pdf',
            canOpenOnGateway: true,
          ),
        );
      },
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'a private PDF whose bytes never arrive is unavailable',
      build: () {
        final waterfall = WaterfallGatewayFallback([
          () => throw Exception('primary gateway is blackholed'),
          () => throw Exception('fallback gateway is blackholed'),
        ]);

        return buildSharedFileCubit(
          item: createPdfItem(size: underLimitFileSize),
          fileKey: SecretKey([1, 2, 3]),
          gatewayFallback: waterfall,
        );
      },
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        // No plaintext, and no URL to offer instead.
        expect(cubit.state, isA<FsEntryPreviewUnavailable>());
        expect(cubit.state, isNot(isA<FsEntryPreviewPdf>()));
      },
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'a type nothing can preview is still unavailable',
      build: () => buildSharedFileCubit(
        item: createItem(
          size: underLimitFileSize,
          name: 'archive.zip',
          contentType: 'application/zip',
        ),
      ),
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        expect(cubit.state, isA<FsEntryPreviewUnavailable>());
        expectNoBytesFetched();
      },
    );
  });
}
