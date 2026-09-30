import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/services/services.dart';
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

/// A data transaction carrying real tags.
///
/// `getTag` is an extension over [TransactionCommonMixin.tags], so stubbing
/// `getTag` on a mock is never consulted - the extension reads `tags` itself.
class _TransactionWithTags extends Fake implements TransactionCommonMixin {
  _TransactionWithTags(this._tags);

  final Map<String, String> _tags;

  @override
  List<TransactionCommonMixin$Tag> get tags => _tags.entries
      .map((entry) => TransactionCommonMixin$Tag()
        ..name = entry.key
        ..value = entry.value)
      .toList();
}

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
  Future<http.Response> fetchData(
    String txId,
    Arweave primaryClient, {
    FetchProgress? onProgress,
  }) async {
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
    String? cipher,
    String? cipherIv,
    bool publicIsUnconfirmed = false,
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
      cipher: cipher,
      cipherIv: cipherIv,
      publicIsUnconfirmed: publicIsUnconfirmed,
    );
  }

  /// Makes the whole private path work: bytes from the gateway, cipher tags
  /// from the transaction, plaintext from the crypto.
  void stubPrivateFetchAndDecrypt({
    List<int> fetched = const [1, 2, 3, 4],
    List<int> decrypted = const [5, 6, 7, 8],
  }) {
    when(() => mockGatewayFallback.fetchData(any(), any(),
        onProgress: any(named: 'onProgress'))).thenAnswer(
      (_) async => http.Response.bytes(fetched, 200),
    );
    when(() => mockArweaveService.getTransactionDetails(any()))
        .thenAnswer((_) async => MockTransactionCommonMixin());
    when(() => mockCrypto.decryptDataFromTransaction(any(), any(), any()))
        .thenAnswer((_) async => Uint8List.fromList(decrypted));
  }

  void expectNoBytesFetched() {
    verifyNever(() => mockArweaveService.gatewayFallback);
    verifyNever(() => mockGatewayFallback.fetchData(any(), any(),
        onProgress: any(named: 'onProgress')));
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
        when(() => mockGatewayFallback.fetchData(any(), any(),
            onProgress: any(named: 'onProgress'))).thenAnswer(
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
        verify(() => mockGatewayFallback.fetchData(dataTxId, any(),
            onProgress: any(named: 'onProgress'))).called(1);
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
        // The bytes are in; decryption is its own step, said as one.
        const FsEntryPreviewLoading(
          phase: FsEntryPreviewLoadPhase.decrypting,
        ),
        const FsEntryPreviewVideo(
          previewUrl: 'blob:fake/0-video/mp4',
          filename: 'clip.mp4',
        ),
      ],
      verify: (cubit) {
        verify(() => mockGatewayFallback.fetchData(dataTxId, any(),
            onProgress: any(named: 'onProgress'))).called(1);
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
        // The bytes are in; decryption is its own step, said as one.
        const FsEntryPreviewLoading(
          phase: FsEntryPreviewLoadPhase.decrypting,
        ),
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
  group('FsEntryPreviewCubit a link that never said the file was private', () {
    // The counterpart of the refusal in `shared_file_download_cubit.dart`. A
    // download that refuses to save ciphertext while the preview beside it
    // paints that same ciphertext as the file is two answers to one question -
    // and the preview is the one the recipient sees first.

    test(
        'paints first, then retracts once the transaction says it is '
        'encrypted', () async {
      // Driven by hand rather than by `blocTest`, because the two halves of
      // this are a race and the point is which one does *not* wait for the
      // other: an auto-completing stub lets the check win and proves only half
      // of it.
      final lookup = Completer<TransactionCommonMixin?>();

      when(() => mockArweaveService.getTransactionDetails(any()))
          .thenAnswer((_) => lookup.future);

      final cubit = buildSharedFileCubit(
        item: createVideoItem(size: underLimitFileSize),
        publicIsUnconfirmed: true,
      );

      final seen = <FsEntryPreviewState>[];
      final sub = cubit.stream.listen(seen.add);

      await pumpEventQueue();

      // The check has not answered, and the preview did not wait for it - the
      // whole reason it runs beside the preview instead of in front of it.
      expect(seen, [
        const FsEntryPreviewVideo(
          previewUrl: '$gatewayUrl/$dataTxId',
          filename: 'clip.mp4',
        ),
      ]);

      lookup.complete(
        _TransactionWithTags(const {EntityTag.cipher: 'AES256-GCM'}),
      );
      await pumpEventQueue();

      // And then it is taken back.
      expect(seen.last, isA<FsEntryPreviewUnavailable>());

      await sub.cancel();
      await cubit.close();
    });

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'leaves a genuinely public preview alone',
      build: () {
        when(() => mockArweaveService.getTransactionDetails(any()))
            .thenAnswer((_) async => _TransactionWithTags(const {}));

        return buildSharedFileCubit(
          item: createVideoItem(size: underLimitFileSize),
          publicIsUnconfirmed: true,
        );
      },
      wait: const Duration(milliseconds: 100),
      expect: () => [
        const FsEntryPreviewVideo(
          previewUrl: '$gatewayUrl/$dataTxId',
          filename: 'clip.mp4',
        ),
      ],
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'a check that cannot be made leaves the preview alone',
      build: () {
        // Not evidence of encryption, and the preview was optimistic either
        // way. The download makes its own check before writing anything.
        when(() => mockArweaveService.getTransactionDetails(any()))
            .thenThrow(Exception('gateway is unreachable'));

        return buildSharedFileCubit(
          item: createVideoItem(size: underLimitFileSize),
          publicIsUnconfirmed: true,
        );
      },
      wait: const Duration(milliseconds: 100),
      expect: () => [
        const FsEntryPreviewVideo(
          previewUrl: '$gatewayUrl/$dataTxId',
          filename: 'clip.mp4',
        ),
      ],
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'costs nothing once the file has been shown to be public',
      build: () => buildSharedFileCubit(
        item: createVideoItem(size: underLimitFileSize),
      ),
      wait: const Duration(milliseconds: 100),
      verify: (_) {
        // `publicIsUnconfirmed` false means the metadata parsed as plaintext,
        // which is proof: encrypted metadata does not parse. Nothing to ask.
        verifyNever(() => mockArweaveService.getTransactionDetails(any()));
      },
    );
  });

  group('FsEntryPreviewCubit link-supplied cipher', () {
    late FakePreviewObjectUrls objectUrls;

    setUp(() => objectUrls = FakePreviewObjectUrls());

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'decrypts with the cipher it was given, without describing the '
      'transaction',
      build: () {
        stubPrivateFetchAndDecrypt();
        when(() => mockCrypto.decryptDataWithCipher(any(), any(), any(), any()))
            .thenAnswer((_) async => Uint8List.fromList([5, 6, 7, 8]));

        return buildSharedFileCubit(
          item: createVideoItem(size: underLimitFileSize),
          fileKey: SecretKey([1, 2, 3]),
          objectUrls: objectUrls,
          cipher: 'AES256-GCM',
          cipherIv: 'aXY=',
        );
      },
      wait: const Duration(milliseconds: 100),
      expect: () => [
        const FsEntryPreviewLoading(),
        // The bytes are in; decryption is its own step, said as one.
        const FsEntryPreviewLoading(
          phase: FsEntryPreviewLoadPhase.decrypting,
        ),
        const FsEntryPreviewVideo(
          previewUrl: 'blob:fake/0-video/mp4',
          filename: 'clip.mp4',
        ),
      ],
      verify: (cubit) {
        // The whole point: a share link that carried `c` and `iv` costs the
        // recipient no GraphQL to preview what it named.
        verifyNever(() => mockArweaveService.getTransactionDetails(any()));
        verifyNever(
          () => mockCrypto.decryptDataFromTransaction(any(), any(), any()),
        );
        verify(
          () => mockCrypto.decryptDataWithCipher(
              'AES256-GCM', 'aXY=', any(), any()),
        ).called(1);

        // Still the decrypted bytes that reach the player.
        expect(
            objectUrls.createdBytes.single, Uint8List.fromList([5, 6, 7, 8]));
      },
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'a private image decrypts from the link cipher too',
      build: () {
        // Images take their own branch on the share page
        // (`_previewImageSharePage`) and hand their bytes to a notifier rather
        // than to a state, so "video works" does not establish that images do.
        stubPrivateFetchAndDecrypt();
        when(() => mockCrypto.decryptDataWithCipher(any(), any(), any(), any()))
            .thenAnswer((_) async => Uint8List.fromList([5, 6, 7, 8]));

        return buildSharedFileCubit(
          item: createImageItem(size: underLimitFileSize),
          fileKey: SecretKey([1, 2, 3]),
          cipher: 'AES256-GCM',
          cipherIv: 'aXY=',
        );
      },
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        verifyNever(() => mockArweaveService.getTransactionDetails(any()));
        verify(
          () => mockCrypto.decryptDataWithCipher(
              'AES256-GCM', 'aXY=', any(), any()),
        ).called(1);

        // The picture the viewer renders is the decrypted one, not the
        // ciphertext that was fetched.
        final notified = FsEntryPreviewCubit.imagePreviewNotifier.value;
        expect(notified, isNotNull);
        expect(notified!.dataBytes, Uint8List.fromList([5, 6, 7, 8]));
        expect(notified.isPreviewable, isTrue);
      },
    );

    blocTest<FsEntryPreviewCubit, FsEntryPreviewState>(
      'falls back to the lookup when it was given no cipher',
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
        // The bytes are in; decryption is its own step, said as one.
        const FsEntryPreviewLoading(
          phase: FsEntryPreviewLoadPhase.decrypting,
        ),
        const FsEntryPreviewVideo(
          previewUrl: 'blob:fake/0-video/mp4',
          filename: 'clip.mp4',
        ),
      ],
      verify: (cubit) {
        // A v1 link, or a version the link never described, still resolves the
        // tags the only other way there is.
        verify(() => mockArweaveService.getTransactionDetails(any())).called(1);
        verify(
          () => mockCrypto.decryptDataFromTransaction(any(), any(), any()),
        ).called(1);
      },
    );
  });

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

        verify(() => mockGatewayFallback.fetchData(dataTxId, any(),
            onProgress: any(named: 'onProgress'))).called(1);
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
      'a private PDF whose bytes never arrive fails, and can be tried again',
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
        // No plaintext and no URL to offer instead - but not "unavailable"
        // either: this is a download that failed, and it says so.
        expect(
          cubit.state,
          const FsEntryPreviewFailed(FsEntryPreviewFailure.download),
        );
        expect((cubit.state as FsEntryPreviewFailed).canRetry, isTrue);
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

  /// The drive explorer previews once immediately and again for every row the
  /// file's database watch emits - and drift emits the current row the moment
  /// the watch starts. A buffered preview must be fetched once for all of
  /// that: a second fetch is up to a hundred megabytes again, and for media it
  /// replaced the playing video with a new one, from the start.
  group('FsEntryPreviewCubit fetches a buffered preview once', () {
    late StreamController<FileEntry> rows;
    late FakePreviewObjectUrls objectUrls;

    setUp(() {
      rows = StreamController<FileEntry>();
      objectUrls = FakePreviewObjectUrls();
    });

    tearDown(() => rows.close());

    FileEntry row({
      required String name,
      required String contentType,
      String txId = dataTxId,
    }) =>
        createMockFileEntry(
          id: fileId,
          driveId: driveId,
          name: name,
          dataTxId: txId,
          dataContentType: contentType,
          size: underLimitFileSize,
        );

    /// An explorer cubit on a private drive whose file row is [rows]. With
    /// [lookUpKey] the file key is not handed in, so the cubit looks it up.
    FsEntryPreviewCubit explorerCubit(
      FileDataTableItem item, {
      bool lookUpKey = false,
    }) {
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
      when(() => fileSelectable.watchSingle()).thenAnswer((_) => rows.stream);

      return FsEntryPreviewCubit(
        driveId: driveId,
        maybeSelectedItem: item,
        driveDao: mockDriveDao,
        configService: mockConfigService,
        arweave: mockArweaveService,
        profileCubit: mockProfileCubit,
        crypto: mockCrypto,
        fileKey: lookUpKey ? null : SecretKey([1, 2, 3]),
        objectUrls: objectUrls,
      );
    }

    /// A key lookup that throws the first time it is asked, and finds the key
    /// after that - a database that was busy, then was not.
    void stubKeyLookupThatThrowsOnce() {
      var asked = 0;
      when(() => mockProfileCubit.state).thenAnswer((_) {
        if (asked++ == 0) throw Exception('database is locked');
        return ProfileLoggingOut();
      });
      when(() => mockDriveDao.getDriveKeyFromMemory(driveId))
          .thenAnswer((_) async => DriveKey(SecretKey([9]), false));
      when(() => mockDriveDao.getFileKey(fileId, any()))
          .thenAnswer((_) async => SecretKey([1, 2, 3]));
    }

    Future<void> settle() => Future.delayed(const Duration(milliseconds: 30));

    /// Each time a download begins from nothing. Decrypting, and progress
    /// along the way, are not new downloads.
    Iterable<FsEntryPreviewLoading> downloadStarts(
      List<FsEntryPreviewState> states,
    ) =>
        states.whereType<FsEntryPreviewLoading>().where((s) =>
            s.phase == FsEntryPreviewLoadPhase.downloading && s.received == 0);

    int fetches(String txId) =>
        verify(() => mockGatewayFallback.fetchData(txId, any(),
            onProgress: any(named: 'onProgress'))).callCount;

    test(
        'a private video is fetched once on opening, and not again on a '
        'later write to its row', () async {
      stubPrivateFetchAndDecrypt();
      final videoRow = row(name: 'clip.mp4', contentType: 'video/mp4');
      final cubit = explorerCubit(createVideoItem(size: underLimitFileSize));
      final states = <FsEntryPreviewState>[];
      final sub = cubit.stream.listen(states.add);

      await settle();
      rows.add(videoRow); // what drift emits as the watch starts
      await settle();
      rows.add(videoRow); // an upload being confirmed, a sync
      await settle();

      expect(fetches(dataTxId), 1);
      expect(objectUrls.created, hasLength(1));
      expect(cubit.state, isA<FsEntryPreviewVideo>());
      expect(downloadStarts(states), hasLength(1),
          reason: 'a second spinner is the playing video being replaced');

      await sub.cancel();
      await cubit.close();
    });

    test('a fetch that failed is tried again on the next write to the row',
        () async {
      stubPrivateFetchAndDecrypt();
      var gatewaysDown = true;
      when(() => mockGatewayFallback.fetchData(any(), any(),
          onProgress: any(named: 'onProgress'))).thenAnswer(
        (_) async {
          if (gatewaysDown) throw Exception('every gateway failed');
          return http.Response.bytes([1, 2, 3, 4], 200);
        },
      );
      final videoRow = row(name: 'clip.mp4', contentType: 'video/mp4');
      final cubit = explorerCubit(createVideoItem(size: underLimitFileSize));

      await settle();
      rows.add(videoRow);
      await settle();
      expect(
        cubit.state,
        const FsEntryPreviewFailed(FsEntryPreviewFailure.download),
      );
      // Reading a count through `verify` resets it, so the next [fetches]
      // counts only what happens after this line.
      final failedAttempts = fetches(dataTxId);

      gatewaysDown = false;
      rows.add(videoRow);
      await settle();

      expect(fetches(dataTxId), 1,
          reason: 'after $failedAttempts failed attempt(s), exactly one more');
      expect(cubit.state, isA<FsEntryPreviewVideo>());

      await cubit.close();
    });

    test('a private document is fetched once, and shown once', () async {
      stubPrivateFetchAndDecrypt(decrypted: 'hello'.codeUnits);
      final textRow = row(name: 'notes.txt', contentType: 'text/plain');
      final cubit = explorerCubit(createItem(
        size: underLimitFileSize,
        name: 'notes.txt',
        contentType: 'text/plain',
      ));
      final states = <FsEntryPreviewState>[];
      final sub = cubit.stream.listen(states.add);

      await settle();
      rows.add(textRow);
      await settle();
      rows.add(textRow);
      await settle();

      expect(fetches(dataTxId), 1);
      expect(cubit.state, isA<FsEntryPreviewText>());
      expect(downloadStarts(states), hasLength(1),
          reason: 'a second spinner resets the text the reader is in');

      await sub.cancel();
      await cubit.close();
    });
    test('a key lookup that throws leaves the video free to try again',
        () async {
      stubPrivateFetchAndDecrypt();
      stubKeyLookupThatThrowsOnce();
      final videoRow = row(name: 'clip.mp4', contentType: 'video/mp4');
      final cubit = explorerCubit(
        createVideoItem(size: underLimitFileSize),
        lookUpKey: true,
      );

      await settle();
      expect(cubit.state, isA<FsEntryPreviewUnavailable>());

      rows.add(videoRow);
      await settle();

      expect(cubit.state, isA<FsEntryPreviewVideo>(),
          reason: 'a claim kept by the throw would refuse this retry');

      await cubit.close();
    });

    test('a key lookup that throws leaves the PDF free to try again', () async {
      stubPrivateFetchAndDecrypt();
      stubKeyLookupThatThrowsOnce();
      final pdfRow = row(name: 'Q3 Report.pdf', contentType: 'application/pdf');
      final cubit = explorerCubit(
        createPdfItem(size: underLimitFileSize),
        lookUpKey: true,
      );

      await settle();
      expect(cubit.state, isA<FsEntryPreviewUnavailable>());

      rows.add(pdfRow);
      await settle();

      expect(cubit.state, isA<FsEntryPreviewPdf>());

      await cubit.close();
    });

    test('the row can correct a guessed type, and the guess stays quiet',
        () async {
      stubPrivateFetchAndDecrypt();

      // The immediate preview guesses text from the item; the row says PDF.
      // The text load is the slow one, so it finishes after the PDF has
      // been shown - and must not paint over it when it does.
      final textBytes = Completer<http.Response>();
      var calls = 0;
      when(() => mockGatewayFallback.fetchData(any(), any(),
          onProgress: any(named: 'onProgress'))).thenAnswer(
        (_) => calls++ == 0
            ? textBytes.future
            : Future.value(http.Response.bytes([1, 2, 3, 4], 200)),
      );

      final cubit = explorerCubit(createItem(
        size: underLimitFileSize,
        name: 'report',
        contentType: 'text/plain',
      ));

      await settle();
      expect(cubit.state, isA<FsEntryPreviewLoading>());

      rows.add(row(name: 'report', contentType: 'application/pdf'));
      await settle();
      expect(cubit.state, isA<FsEntryPreviewPdf>(),
          reason: "the text load's claim must not shut out the PDF");

      textBytes.complete(http.Response.bytes([1, 2, 3, 4], 200));
      await settle();

      expect(cubit.state, isA<FsEntryPreviewPdf>(),
          reason: 'the superseded text load must not publish');

      await cubit.close();
    });
    test('a superseded video gives its decrypted bytes back', () async {
      stubPrivateFetchAndDecrypt();

      // The video load is held open; the row then says the file is a PDF,
      // which takes the claim over. When the video's bytes arrive they are
      // decrypted into a URL - which must be revoked, not kept until close.
      final videoBytes = Completer<http.Response>();
      var calls = 0;
      when(() => mockGatewayFallback.fetchData(any(), any(),
          onProgress: any(named: 'onProgress'))).thenAnswer(
        (_) => calls++ == 0
            ? videoBytes.future
            : Future.value(http.Response.bytes([1, 2, 3, 4], 200)),
      );

      final cubit = explorerCubit(createVideoItem(size: underLimitFileSize));

      await settle();
      rows.add(row(name: 'clip.mp4', contentType: 'application/pdf'));
      await settle();
      expect(cubit.state, isA<FsEntryPreviewPdf>());

      videoBytes.complete(http.Response.bytes([1, 2, 3, 4], 200));
      await settle();

      expect(cubit.state, isA<FsEntryPreviewPdf>());
      expect(objectUrls.created, hasLength(1));
      expect(objectUrls.revoked, objectUrls.created,
          reason: 'a superseded load must not hold decrypted media');

      await cubit.close();
    });
  });

  /// #2206: a private file of tens of MiB used to sit behind a bare spinner
  /// until it arrived, and a failure looked exactly like a file type that is
  /// never previewed - with no way to try again.
  group('FsEntryPreviewCubit says how far a preview has got', () {
    late FakePreviewObjectUrls objectUrls;

    setUp(() => objectUrls = FakePreviewObjectUrls());

    /// A gateway that reports [reports] through the preview's progress
    /// callback, [gap] apart, and then answers.
    void stubFetchReporting(
      List<(int, int?)> reports, {
      Duration gap = Duration.zero,
    }) {
      when(() => mockGatewayFallback.fetchData(any(), any(),
          onProgress: any(named: 'onProgress'))).thenAnswer((invocation) async {
        final onProgress =
            invocation.namedArguments[#onProgress] as FetchProgress?;

        for (final (received, total) in reports) {
          if (gap > Duration.zero) await Future<void>.delayed(gap);
          onProgress?.call(received, total);
        }

        return http.Response.bytes([1, 2, 3, 4], 200);
      });
    }

    FsEntryPreviewCubit privateVideo() => buildSharedFileCubit(
          item: createVideoItem(size: underLimitFileSize),
          fileKey: SecretKey([1, 2, 3]),
          objectUrls: objectUrls,
        );

    int fetches() => verify(() => mockGatewayFallback.fetchData(any(), any(),
        onProgress: any(named: 'onProgress'))).callCount;

    test('counts the download, then says it is decrypting, then plays',
        () async {
      stubPrivateFetchAndDecrypt();
      stubFetchReporting(
        [(0, 400), (100, 400), (200, 400), (400, 400)],
        gap: const Duration(milliseconds: 120),
      );

      final cubit = privateVideo();
      final states = <FsEntryPreviewState>[];
      final sub = cubit.stream.listen(states.add);
      await Future<void>.delayed(const Duration(milliseconds: 800));

      final loading = states.whereType<FsEntryPreviewLoading>().toList();
      final downloading = loading
          // The first Loading comes before any gateway has answered, so it
          // knows no length; everything after it is the gateway's own count.
          .where((s) =>
              s.phase == FsEntryPreviewLoadPhase.downloading && s.total != null)
          .map((s) => s.received)
          .toList();

      expect(downloading, [0, 100, 200, 400]);
      expect(loading.last.phase, FsEntryPreviewLoadPhase.decrypting);
      expect(loading.last.fraction, isNull,
          reason: 'decryption has no progress to show, and none is faked');
      expect(states.last, isA<FsEntryPreviewVideo>());

      await sub.cancel();
      await cubit.close();
    });

    test('reports no faster than it can be drawn, and never skips the end',
        () async {
      stubPrivateFetchAndDecrypt();
      // A thousand chunks with no time between them: a report for each would
      // rebuild the preview a thousand times to move a bar a pixel.
      stubFetchReporting([
        for (var i = 0; i <= 1000; i++) (i, 1000),
      ]);

      final cubit = privateVideo();
      final states = <FsEntryPreviewState>[];
      final sub = cubit.stream.listen(states.add);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final received = states
          .whereType<FsEntryPreviewLoading>()
          .where((s) => s.phase == FsEntryPreviewLoadPhase.downloading)
          .map((s) => s.received)
          .toList();

      expect(received.length, lessThan(5));
      expect(received.last, 1000);

      await sub.cancel();
      await cubit.close();
    });

    test('a fraction is only claimed when the gateway declared a length', () {
      expect(
        const FsEntryPreviewLoading(received: 50, total: 200).fraction,
        0.25,
      );
      expect(const FsEntryPreviewLoading(received: 50).fraction, isNull);
      expect(
        const FsEntryPreviewLoading(received: 500, total: 200).fraction,
        1.0,
        reason: 'a gateway that sent more than it declared still reads full',
      );
    });

    test('a download that fails can be tried again, and the retry fetches',
        () async {
      stubPrivateFetchAndDecrypt();
      var gatewaysDown = true;
      when(() => mockGatewayFallback.fetchData(any(), any(),
          onProgress: any(named: 'onProgress'))).thenAnswer((_) async {
        if (gatewaysDown) throw Exception('every gateway failed');
        return http.Response.bytes([1, 2, 3, 4], 200);
      });

      final cubit = privateVideo();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        cubit.state,
        const FsEntryPreviewFailed(FsEntryPreviewFailure.download),
      );
      expect(cubit.state, isNot(isA<FsEntryPreviewUnavailable>()),
          reason: 'unavailable hides the preview; a failure must not');
      final failed = fetches();

      gatewaysDown = false;
      await cubit.retry();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fetches(), 1, reason: 'after $failed, exactly one more');
      expect(cubit.state, isA<FsEntryPreviewVideo>());

      await cubit.close();
    });

    test('bytes that will not decrypt are not fetched again', () async {
      stubPrivateFetchAndDecrypt();
      when(() => mockCrypto.decryptDataFromTransaction(any(), any(), any()))
          .thenThrow(Exception('bad padding'));

      final cubit = privateVideo();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        cubit.state,
        const FsEntryPreviewFailed(FsEntryPreviewFailure.decrypt),
      );
      expect((cubit.state as FsEntryPreviewFailed).canRetry, isFalse);
      fetches();

      await cubit.retry();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      verifyNever(() => mockGatewayFallback.fetchData(any(), any(),
          onProgress: any(named: 'onProgress')));
      expect(
        cubit.state,
        const FsEntryPreviewFailed(FsEntryPreviewFailure.decrypt),
      );

      await cubit.close();
    });

    test('not finding how the file is encrypted is the network, not the file',
        () async {
      stubPrivateFetchAndDecrypt();
      // The bytes arrived; the lookup of the cipher tags did not.
      when(() => mockArweaveService.getTransactionDetails(any()))
          .thenAnswer((_) async => null);

      final cubit = privateVideo();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        cubit.state,
        const FsEntryPreviewFailed(FsEntryPreviewFailure.download),
      );
      verifyNever(
        () => mockCrypto.decryptDataFromTransaction(any(), any(), any()),
      );

      await cubit.close();
    });

    test('retry does nothing unless the preview failed', () async {
      stubPrivateFetchAndDecrypt();

      final cubit = privateVideo();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(cubit.state, isA<FsEntryPreviewVideo>());
      fetches();

      await cubit.retry();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      verifyNever(() => mockGatewayFallback.fetchData(any(), any(),
          onProgress: any(named: 'onProgress')));
      expect(cubit.state, isA<FsEntryPreviewVideo>());

      await cubit.close();
    });

    test('a private document says how far it has got, and can be retried',
        () async {
      stubPrivateFetchAndDecrypt(decrypted: 'hello'.codeUnits);
      var gatewaysDown = true;
      when(() => mockGatewayFallback.fetchData(any(), any(),
          onProgress: any(named: 'onProgress'))).thenAnswer((invocation) async {
        if (gatewaysDown) throw Exception('every gateway failed');
        (invocation.namedArguments[#onProgress] as FetchProgress?)?.call(4, 4);
        return http.Response.bytes([1, 2, 3, 4], 200);
      });

      final cubit = buildSharedFileCubit(
        item: createItem(
          size: underLimitFileSize,
          name: 'notes.txt',
          contentType: 'text/plain',
        ),
        fileKey: SecretKey([1, 2, 3]),
      );
      final states = <FsEntryPreviewState>[];
      final sub = cubit.stream.listen(states.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        cubit.state,
        const FsEntryPreviewFailed(FsEntryPreviewFailure.download),
      );

      gatewaysDown = false;
      await cubit.retry();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cubit.state, isA<FsEntryPreviewText>());
      expect(
        states.whereType<FsEntryPreviewLoading>().map((s) => s.received),
        contains(4),
      );

      await sub.cancel();
      await cubit.close();
    });
  });

  group('FsEntryPreviewCubit progress for a load that was taken over', () {
    test('a superseded download reports nothing more', () async {
      final drive = MockDrive();
      final driveSelectable = MockSelectable<Drive>();
      final fileSelectable = MockSelectable<FileEntry>();
      final rows = StreamController<FileEntry>();
      addTearDown(rows.close);

      when(() => drive.privacy).thenReturn(DrivePrivacyTag.private);
      when(() => mockDriveDao.driveById(driveId: driveId))
          .thenReturn(driveSelectable);
      when(() => driveSelectable.getSingleOrNull())
          .thenAnswer((_) async => drive);
      when(() => driveSelectable.getSingle()).thenAnswer((_) async => drive);
      when(() => mockDriveDao.fileById(fileId: fileId))
          .thenReturn(fileSelectable);
      when(() => fileSelectable.watchSingle()).thenAnswer((_) => rows.stream);
      when(() => mockArweaveService.getTransactionDetails(any()))
          .thenAnswer((_) async => MockTransactionCommonMixin());
      when(() => mockCrypto.decryptDataFromTransaction(any(), any(), any()))
          .thenAnswer((_) async => Uint8List.fromList([5, 6, 7, 8]));

      // The video's download reports late, after the row has said the file is
      // a PDF and the PDF has taken the screen.
      final videoProgress = Completer<FetchProgress?>();
      final videoDone = Completer<http.Response>();
      var calls = 0;
      when(() => mockGatewayFallback.fetchData(any(), any(),
          onProgress: any(named: 'onProgress'))).thenAnswer((invocation) {
        if (calls++ == 0) {
          videoProgress.complete(
              invocation.namedArguments[#onProgress] as FetchProgress?);
          return videoDone.future;
        }
        return Future.value(http.Response.bytes([1, 2, 3, 4], 200));
      });

      final cubit = FsEntryPreviewCubit(
        driveId: driveId,
        maybeSelectedItem: createVideoItem(size: underLimitFileSize),
        driveDao: mockDriveDao,
        configService: mockConfigService,
        arweave: mockArweaveService,
        profileCubit: mockProfileCubit,
        crypto: mockCrypto,
        fileKey: SecretKey([1, 2, 3]),
        objectUrls: FakePreviewObjectUrls(),
      );
      final states = <FsEntryPreviewState>[];
      final sub = cubit.stream.listen(states.add);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      rows.add(createMockFileEntry(
        id: fileId,
        driveId: driveId,
        name: 'clip.mp4',
        dataTxId: dataTxId,
        dataContentType: 'application/pdf',
        size: underLimitFileSize,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(cubit.state, isA<FsEntryPreviewPdf>());

      final lateReport = await videoProgress.future;
      states.clear();
      lateReport?.call(3, 4);
      videoDone.complete(http.Response.bytes([1, 2, 3, 4], 200));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(states, isEmpty,
          reason: 'a superseded load must not move a bar that is not its own');
      expect(cubit.state, isA<FsEntryPreviewPdf>());

      await sub.cancel();
      await cubit.close();
    });
  });
}
