import 'dart:typed_data';

import 'package:ardrive/pages/shared_file/shared_file_identity.dart';
import 'package:ardrive/pages/shared_file/shared_file_thumbnail.dart';
import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

class MockDataGatewayFallback extends Mock implements DataGatewayFallback {}

/// Mimics [DataGatewayFallback]'s serial waterfall: every entry of [gateways]
/// is tried in order and the first one that does not throw wins.
class WaterfallGatewayFallback extends Mock implements DataGatewayFallback {
  WaterfallGatewayFallback(this.gateways);

  final List<Future<Uint8List?> Function()> gateways;
  final List<int> attemptedGateways = [];

  @override
  Future<Uint8List?> fetchDataAtMost(
    String txId,
    Arweave primaryClient, {
    required int maxBytes,
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

/// A loader that answers from memory, and records what it was asked for.
class FakeThumbnailLoader extends SharedFileThumbnailLoader {
  FakeThumbnailLoader({required super.arweave, this.bytes});

  final Uint8List? bytes;

  /// Every `(txId, isPrivate, fileKey)` this loader was asked for.
  final List<(String, bool, SecretKey?)> requests = [];

  @override
  Future<Uint8List?> load({
    required String txId,
    required bool isPrivate,
    SecretKey? fileKey,
  }) async {
    requests.add((txId, isPrivate, fileKey));

    return bytes;
  }
}

/// A 1x1 transparent PNG - real bytes, so nothing in the image pipeline has to
/// deal with a broken one.
final transparentPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

/// The recipient-side thumbnail (review F15).
///
/// The drive explorer's `ThumbnailRepository` starts with a local-DB drive
/// lookup, which a recipient can never satisfy, so the share page loads
/// thumbnails through this instead: the shared gateway waterfall, plus the
/// recipient's own access key for a private file's encrypted thumbnail.
void main() {
  const thumbnailTxId = 'thumbnail-tx-id';

  late MockArweaveService mockArweaveService;
  late MockArweave mockArweaveClient;
  late MockArDriveCrypto mockCrypto;
  late MockDataGatewayFallback mockGatewayFallback;

  setUpAll(() {
    registerFallbackValue(MockArweave());
    registerFallbackValue(MockTransactionCommonMixin());
    registerFallbackValue(SecretKey([]));
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    mockArweaveService = MockArweaveService();
    mockArweaveClient = MockArweave();
    mockCrypto = MockArDriveCrypto();
    mockGatewayFallback = MockDataGatewayFallback();

    when(() => mockArweaveService.client).thenReturn(mockArweaveClient);
    when(() => mockArweaveService.gatewayFallback)
        .thenReturn(mockGatewayFallback);
  });

  SharedFileThumbnailLoader buildLoader({
    DataGatewayFallback? gatewayFallback,
  }) {
    if (gatewayFallback != null) {
      when(() => mockArweaveService.gatewayFallback)
          .thenReturn(gatewayFallback);
    }

    return SharedFileThumbnailLoader(
      arweave: mockArweaveService,
      crypto: mockCrypto,
    );
  }

  test('a public thumbnail comes back as it was fetched', () async {
    when(() => mockGatewayFallback.fetchDataAtMost(any(), any(),
            maxBytes: any(named: 'maxBytes')))
        .thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));

    final bytes = await buildLoader().load(
      txId: thumbnailTxId,
      isPrivate: false,
    );

    expect(bytes, Uint8List.fromList([1, 2, 3]));
    verify(() => mockGatewayFallback.fetchDataAtMost(thumbnailTxId, any(),
        maxBytes: thumbnailPreviewMaxFileSize)).called(1);
    verifyNever(
      () => mockCrypto.decryptDataFromTransaction(any(), any(), any()),
    );
  });

  test('a `thn` that names something enormous is never buffered whole',
      () async {
    // The size check used to run on `response.bodyBytes`, which is a check
    // made *after* paying for every byte it rejects - and `thn` is a field the
    // link's author chooses, so those bytes are somebody else's decision. The
    // cap has to travel with the request.
    when(() => mockGatewayFallback.fetchDataAtMost(any(), any(),
        maxBytes: any(named: 'maxBytes'))).thenAnswer((_) async => null);

    final bytes = await buildLoader().load(
      txId: thumbnailTxId,
      isPrivate: false,
    );

    expect(bytes, isNull);
    verify(() => mockGatewayFallback.fetchDataAtMost(thumbnailTxId, any(),
        maxBytes: thumbnailPreviewMaxFileSize)).called(1);
    // The unbounded fetch is not an implementation detail this page may reach
    // for: it hands back a fully buffered response.
    verifyNever(() => mockGatewayFallback.fetchData(any(), any()));
  });

  test('a dead primary gateway costs nothing', () async {
    final waterfall = WaterfallGatewayFallback([
      () => throw Exception('primary gateway is blackholed'),
      () async => Uint8List.fromList([9, 8, 7]),
    ]);

    final bytes = await buildLoader(gatewayFallback: waterfall).load(
      txId: thumbnailTxId,
      isPrivate: false,
    );

    expect(waterfall.attemptedGateways, [0, 1]);
    expect(bytes, Uint8List.fromList([9, 8, 7]));
  });

  test('a private thumbnail is decrypted with the recipient access key',
      () async {
    final transaction = MockTransactionCommonMixin();
    final fileKey = SecretKey([1, 2, 3]);

    when(() => mockGatewayFallback.fetchDataAtMost(any(), any(),
            maxBytes: any(named: 'maxBytes')))
        .thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));
    when(() => mockArweaveService.getTransactionDetails(any()))
        .thenAnswer((_) async => transaction);
    when(() => mockCrypto.decryptDataFromTransaction(any(), any(), any()))
        .thenAnswer((_) async => Uint8List.fromList([4, 5, 6]));

    final bytes = await buildLoader().load(
      txId: thumbnailTxId,
      isPrivate: true,
      fileKey: fileKey,
    );

    expect(bytes, Uint8List.fromList([4, 5, 6]));

    // The cipher and IV are public tags on the *thumbnail* transaction, so
    // that is the transaction whose details are read.
    verify(() => mockArweaveService.getTransactionDetails(thumbnailTxId))
        .called(1);
    verify(
      () => mockCrypto.decryptDataFromTransaction(
        transaction,
        Uint8List.fromList([1, 2, 3]),
        fileKey,
      ),
    ).called(1);
  });

  test('a private thumbnail without a key is never fetched', () async {
    final bytes = await buildLoader().load(
      txId: thumbnailTxId,
      isPrivate: true,
    );

    expect(bytes, isNull);
    verifyNever(() => mockGatewayFallback.fetchDataAtMost(any(), any(),
        maxBytes: any(named: 'maxBytes')));
    verifyNever(() => mockArweaveService.getTransactionDetails(any()));
    verifyNever(
      () => mockCrypto.decryptDataFromTransaction(any(), any(), any()),
    );
  });

  test('every gateway failing costs the thumbnail, not the page', () async {
    when(() => mockGatewayFallback.fetchDataAtMost(any(), any(),
        maxBytes: any(named: 'maxBytes'))).thenThrow(
      Exception('all gateways failed'),
    );

    final bytes = await buildLoader().load(
      txId: thumbnailTxId,
      isPrivate: false,
    );

    expect(bytes, isNull);
  });

  group('on the recipient card', () {
    Widget wrap(Widget child) => ArDriveTheme(
          themeData: lightTheme(),
          child: MaterialApp(home: Scaffold(body: child)),
        );

    testWidgets('the thumbnail replaces the type icon once it arrives',
        (tester) async {
      await tester.pumpWidget(
        wrap(
          SharedFileIdentity(
            name: 'photo.png',
            size: 1024,
            contentType: 'image/png',
            thumbnailTxId: thumbnailTxId,
            thumbnailLoader: FakeThumbnailLoader(
              arweave: mockArweaveService,
              bytes: transparentPng,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('a private thumbnail is loaded with the recipient access key',
        (tester) async {
      final fileKey = SecretKey([1, 2, 3]);
      final loader = FakeThumbnailLoader(
        arweave: mockArweaveService,
        bytes: transparentPng,
      );

      await tester.pumpWidget(
        wrap(
          SharedFileIdentity(
            name: 'photo.png',
            size: 1024,
            contentType: 'image/png',
            thumbnailTxId: thumbnailTxId,
            isPrivate: true,
            fileKey: fileKey,
            thumbnailLoader: loader,
          ),
        ),
      );

      await tester.pump();

      expect(loader.requests, [(thumbnailTxId, true, fileKey)]);
    });

    testWidgets('a card with no thumbnail asks for nothing', (tester) async {
      final loader = FakeThumbnailLoader(arweave: mockArweaveService);

      await tester.pumpWidget(
        wrap(
          SharedFileIdentity(
            name: 'photo.png',
            size: 1024,
            contentType: 'image/png',
            thumbnailLoader: loader,
          ),
        ),
      );

      await tester.pump();

      expect(loader.requests, isEmpty);
      expect(find.byType(Image), findsNothing);
    });
  });

  test('a thumbnail that will not decrypt is dropped silently', () async {
    when(() => mockGatewayFallback.fetchDataAtMost(any(), any(),
            maxBytes: any(named: 'maxBytes')))
        .thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));
    when(() => mockArweaveService.getTransactionDetails(any()))
        .thenAnswer((_) async => MockTransactionCommonMixin());
    when(() => mockCrypto.decryptDataFromTransaction(any(), any(), any()))
        .thenThrow(Exception('wrong key'));

    final bytes = await buildLoader().load(
      txId: thumbnailTxId,
      isPrivate: true,
      fileKey: SecretKey([1, 2, 3]),
    );

    expect(bytes, isNull);
  });
}
