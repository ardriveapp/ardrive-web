@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/d2n_streamed_upload.dart';
import 'package:ardrive_uploader/src/data_bundler.dart';
import 'package:ardrive_uploader/src/streamed_upload.dart';
import 'package:arweave/arweave.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockDataBundler extends Mock implements DataBundler<TransactionResult> {}

class MockStreamedUploadFactory extends Mock implements StreamedUploadFactory {}

class MockStreamedUpload extends Mock implements StreamedUpload {}

class MockUploadController extends Mock implements UploadController {}

class MockIOFile extends Mock implements IOFile {}

class MockARFSFileUploadMetadata extends Mock
    implements ARFSFileUploadMetadata {}

class MockTransactionResult extends Mock implements TransactionResult {}

class MockWallet extends Mock implements Wallet {}

/// A single-chunk transaction whose chunks can really be streamed. Its
/// signature is never checked: the servers in these tests are fakes.
Future<TransactionResult> _transaction(String id) async {
  final data = Uint8List.fromList(List.generate(10 * 1024, (i) => i % 256));
  final prepared =
      (await prepareChunksTaskEither(() => Stream.value(data)).run())
          .getOrElse((error) => throw error);
  return TransactionResult(
    id: id,
    anchor: 'dGVzdC1hbmNob3I',
    owner: 'b3duZXI',
    tags: [],
    target: '',
    quantity: BigInt.zero,
    dataRoot: prepared.dataRoot,
    dataSize: data.length,
    reward: BigInt.one,
    signature: 'c2lnbmF0dXJl',
    chunkStreamGenerator: () => getChunks(
        Stream.value(data), prepared.chunks, prepared.dataRoot, data.length),
    chunks: prepared.chunks,
  );
}

void main() {
  group('UploadFileUsingBundleStrategy, retrying a signed transaction', () {
    late MockDataBundler bundler;
    late MockStreamedUploadFactory streamedUploadFactory;
    late MockStreamedUpload streamedUpload;
    late MockUploadController controller;
    late UploadFileUsingBundleStrategy strategy;
    late MockTransactionResult previous;
    late FileUploadTask task;

    setUpAll(() {
      registerFallbackValue(FileUploadTask(
        file: MockIOFile(),
        metadata: MockARFSFileUploadMetadata(),
        type: UploadType.d2n,
        uploadThumbnail: false,
      ));
      registerFallbackValue(MockIOFile());
      registerFallbackValue(MockARFSFileUploadMetadata());
      registerFallbackValue(<DataItemFile>[]);
      registerFallbackValue(MockWallet());
      registerFallbackValue(
          TransactionUploadItem(size: 1, data: MockTransactionResult()));
    });

    Future<TransactionResult> Function() whenBundled() =>
        () => bundler.createDataBundle(
              file: any(named: 'file'),
              dataItemFiles: any(named: 'dataItemFiles'),
              metadata: any(named: 'metadata'),
              wallet: any(named: 'wallet'),
              driveKey: any(named: 'driveKey'),
              onStartBundleCreation: any(named: 'onStartBundleCreation'),
              customBundleTags: any(named: 'customBundleTags'),
              onStartMetadataCreation: any(named: 'onStartMetadataCreation'),
              signedDataItemResults: any(named: 'signedDataItemResults'),
            );

    Future<StreamedUploadResult> Function() whenSent() =>
        () => streamedUpload.send(any(), any(), any());

    setUp(() {
      bundler = MockDataBundler();
      streamedUploadFactory = MockStreamedUploadFactory();
      streamedUpload = MockStreamedUpload();
      controller = MockUploadController();
      strategy = UploadFileUsingBundleStrategy(
        dataBundler: bundler,
        streamedUploadFactory: streamedUploadFactory,
      );
      previous = MockTransactionResult();
      when(() => previous.id).thenReturn('previous-tx');

      final metadata = MockARFSFileUploadMetadata();
      when(() => metadata.paidBy).thenReturn([]);
      task = FileUploadTask(
        file: MockIOFile(),
        metadata: metadata,
        type: UploadType.d2n,
        uploadThumbnail: false,
        uploadItem: TransactionUploadItem(size: 10, data: previous),
      );

      when(() => streamedUploadFactory.fromUploadType(any()))
          .thenAnswer((_) async => streamedUpload);
      when(() => controller.updateProgress(task: any(named: 'task')))
          .thenReturn(null);
    });

    Future<void> retry({bool resend = true}) => strategy.upload(
          dataItems: [],
          task: task,
          wallet: MockWallet(),
          controller: controller,
          verifyCancel: () => false,
          signedDataItemResults: [],
          resendSignedTransaction: resend,
        );

    test('sends the same transaction and signs nothing new', () async {
      when(whenSent()).thenAnswer((_) async => StreamedUploadResult(
            success: true,
          ));

      await retry();

      final sent = verify(() => streamedUpload.send(captureAny(), any(), any()))
          .captured
          .single as TransactionUploadItem;
      expect(sent.data.id, 'previous-tx');
      verifyNever(whenBundled());
    });

    test('a failure of that transaction is reported, not replaced', () async {
      when(whenSent()).thenAnswer((_) async => StreamedUploadResult(
            success: false,
            error: Exception('chunk rejected'),
          ));

      await expectLater(retry(), throwsA(isA<BundleUploadException>()));
      verifyNever(whenBundled());
    });

    test(
        'a failed header post is not replaced by a new transaction: '
        'the header may have landed anyway', () async {
      when(whenSent()).thenAnswer((_) async => StreamedUploadResult(
            success: false,
            error: TransactionHeaderNotPostedException(),
          ));

      await expectLater(retry(), throwsA(isA<BundleUploadException>()));

      final sent = verify(() => streamedUpload.send(captureAny(), any(), any()))
          .captured
          .cast<TransactionUploadItem>()
          .map((item) => item.data.id);
      expect(sent, ['previous-tx']);
      verifyNever(whenBundled());
    });

    test('a first attempt builds its transaction as before', () async {
      final built = MockTransactionResult();
      when(() => built.id).thenReturn('built-tx');
      when(() => built.dataSize).thenReturn(10);
      when(whenBundled()).thenAnswer((_) async => built);
      when(whenSent())
          .thenAnswer((_) async => StreamedUploadResult(success: true));

      await retry(resend: false);

      verify(whenBundled()).called(1);
    });
  });

  group('D2NStreamedUpload', () {
    late HttpServer server;
    late int statusCode;
    late int headerStatus;
    late int headerPosts;
    late int chunkPosts;
    late Arweave arweave;

    setUp(() async {
      headerStatus = 200;
      headerPosts = 0;
      chunkPosts = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final path = request.uri.path;
        final response = request.response;
        await request.drain<void>();
        if (path.endsWith('/status')) {
          response.statusCode = statusCode;
        } else if (path == '/tx') {
          headerPosts++;
          response.statusCode = headerStatus;
          response.write(headerStatus == 200 ? 'OK' : 'Refused');
        } else if (path == '/chunk') {
          chunkPosts++;
        } else {
          response.statusCode = 404;
        }
        await response.close();
      });
      arweave = Arweave(
        api: ArweaveApi(
          gatewayUrl: Uri.parse('http://127.0.0.1:${server.port}'),
        ),
      );
    });

    tearDown(() => server.close(force: true));

    Future<StreamedUploadResult> send() async {
      final transaction = await _transaction('tx-id');
      return D2NStreamedUpload(getArweave: () => arweave).send(
        TransactionUploadItem(size: transaction.dataSize, data: transaction),
        MockWallet(),
        null,
      );
    }

    test('posts the header and the chunks of a new transaction', () async {
      statusCode = 404;

      final result = await send();

      expect(result.success, isTrue);
      expect((headerPosts, chunkPosts), (1, 1));
    });

    for (final (status, state) in [(202, 'pending'), (200, 'mined')]) {
      test('posts only the chunks of a $state transaction', () async {
        statusCode = status;

        final result = await send();

        expect(result.success, isTrue);
        expect((headerPosts, chunkPosts), (0, 1));
      });
    }

    test('reports a refused header as not posted', () async {
      statusCode = 404;
      headerStatus = 400;

      final result = await send();

      expect(result.success, isFalse);
      expect(result.error, isA<TransactionHeaderNotPostedException>());
      expect(chunkPosts, 0);
    });
  });
}
