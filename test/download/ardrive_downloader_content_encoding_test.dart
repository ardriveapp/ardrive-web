import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/arweave.dart' show ArweaveApi;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';
import 'download_test_harness.dart';

class _Transaction with TransactionCommonMixin {}

class _MockFallback extends Mock implements DataGatewayFallback {}

class _StubHttpClient extends http.BaseClient {
  _StubHttpClient(this._respond);

  final http.StreamedResponse Function(http.BaseRequest request) _respond;
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return _respond(request);
  }
}

/// A public file stored gzipped (`Content-Encoding: gzip`, a deployment's text
/// and code): what a client hands over is the decoded file, but a `Range`
/// asks for stored bytes. The downloader must not resume such a download, and
/// must not save gzip bytes that were never decoded as if they were the file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const txId = 'nS7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWeR';
  final lastModified = DateTime.utc(2026, 11, 16);

  final script = Uint8List.fromList(
    utf8.encode('function hello() { return "hello"; }\n' * 300),
  );
  final gzipped = Uint8List.fromList(GZipEncoder().encode(script)!);

  late MockArweaveService arweave;

  setUp(() {
    arweave = MockArweaveService();
  });

  ({ArDriveDownloader downloader, RecordingArDriveIO io}) build(
    DownloadSource source,
  ) {
    final io = RecordingArDriveIO();
    return (
      downloader: ArDriveDownloader(
        ioFileAdapter: IOFileAdapter(),
        ardriveIo: io,
        arweave: arweave,
        source: source,
        resumeBackoffStep: Duration.zero,
        verifierFactory: (id) async =>
            StreamedDataItemVerifier.unavailable('not under test'),
      ),
      io: io,
    );
  }

  Future<List<Object>> download(
    ArDriveDownloader downloader, {
    required int fileSize,
    String name = 'app.js',
    String contentType = 'text/javascript',
  }) async {
    final progress = await downloader.downloadFile(
      txId: txId,
      fileSize: fileSize,
      fileName: name,
      lastModifiedDate: lastModified,
      contentType: contentType,
      isManifest: false,
    );
    return drainProgress(progress);
  }

  void tagsSay(String? encoding) {
    final tx = _Transaction()
      ..id = txId
      ..tags = [
        TransactionCommonMixin$Tag()
          ..name = 'Content-Type'
          ..value = 'text/javascript',
        if (encoding != null)
          TransactionCommonMixin$Tag()
            ..name = 'Content-Encoding'
            ..value = encoding,
      ];
    when(() => arweave.getTransactionDetails(txId)).thenAnswer((_) async => tx);
  }

  group('R1: a file stored with a Content-Encoding is not resumed', () {
    test('the response says so: no byte range is ever requested', () async {
      final source = FakeDownloadSource(
        script,
        failAfterBytesOnFirstOpen: 400,
        contentEncoding: 'gzip',
      );
      final harness = build(source);

      final errors =
          await download(harness.downloader, fileSize: script.length);

      expect(
          errors.whereType<DownloadResumeNotSupportedException>(), isNotEmpty);
      expect(source.requestedOffsets, [0]);
    });

    test('the response header is hidden: the tags say so', () async {
      tagsSay('gzip');
      final source = FakeDownloadSource(script, failAfterBytesOnFirstOpen: 400);
      final harness = build(source);

      final errors =
          await download(harness.downloader, fileSize: script.length);

      expect(
          errors.whereType<DownloadResumeNotSupportedException>(), isNotEmpty);
      expect(source.requestedOffsets, [0]);
      verify(() => arweave.getTransactionDetails(txId)).called(1);
    });

    test('a resumed response that declares an encoding is refused', () async {
      tagsSay(null);
      var opens = 0;
      final source = _EncodingOnSecondOpen(script, onOpen: () => opens++);
      final harness = build(source);

      final errors =
          await download(harness.downloader, fileSize: script.length);

      expect(
          errors.whereType<DownloadResumeNotSupportedException>(), isNotEmpty);
      expect(opens, 2);
      // Whatever was saved before the break is not completed with other bytes.
      expect(harness.io.savedBytes.length, lessThan(script.length));
    });

    test('a file with no encoding resumes as it always did', () async {
      tagsSay(null);
      final source = FakeDownloadSource(script, failAfterBytesOnFirstOpen: 400);
      final harness = build(source);

      expect(
          await download(harness.downloader, fileSize: script.length), isEmpty);
      expect(harness.io.savedBytes, script);
      expect(source.requestedOffsets, [0, 400]);
    });

    test('a tag lookup that fails does not stop a resume', () async {
      when(() => arweave.getTransactionDetails(txId))
          .thenAnswer((_) async => throw Exception('graphql down'));
      final source = FakeDownloadSource(script, failAfterBytesOnFirstOpen: 400);
      final harness = build(source);

      expect(
          await download(harness.downloader, fileSize: script.length), isEmpty);
      expect(harness.io.savedBytes, script);
      expect(source.requestedOffsets, [0, 400]);
    });

    test('an identity encoding is not an encoding', () {
      expect(isEncodedContentEncoding(null), isFalse);
      expect(isEncodedContentEncoding(''), isFalse);
      expect(isEncodedContentEncoding('identity'), isFalse);
      expect(isEncodedContentEncoding('gzip'), isTrue);
      expect(isEncodedContentEncoding(' GZIP '), isTrue);
      expect(isEncodedContentEncoding('br'), isTrue);
    });

    test('a decoded download of a tagged file saves the file', () async {
      final source = FakeDownloadSource(script, contentEncoding: 'gzip');
      final harness = build(source);

      expect(
          await download(harness.downloader, fileSize: script.length), isEmpty);
      expect(harness.io.savedBytes, script);
    });
  });

  group('R3: the request for byte 0 is a plain GET', () {
    ({GatewayDownloadSource source, _StubHttpClient client}) build(
      http.StreamedResponse Function(http.BaseRequest request) respond,
    ) {
      final client = _StubHttpClient(respond);
      final arweaveService = MockArweaveService();
      final arweaveClient = MockArweave();
      final fallback = _MockFallback();
      when(() => arweaveService.client).thenReturn(arweaveClient);
      when(() => arweaveClient.api).thenReturn(
        ArweaveApi(gatewayUrl: Uri.parse('https://arweave.net')),
      );
      when(() => arweaveService.gatewayFallback).thenReturn(fallback);
      when(() => fallback.cachedGateways).thenReturn(null);
      return (
        source:
            GatewayDownloadSource(arweaveService, clientFactory: () => client),
        client: client,
      );
    }

    test('no Range header at byte 0: Chrome cannot decode a ranged gzip',
        () async {
      final harness = build((request) => http.StreamedResponse(
            Stream<List<int>>.fromIterable([script]),
            200,
            headers: const {'content-encoding': 'gzip'},
          ));

      final response = await harness.source.open(txId: txId);

      expect(
          harness.client.requests.single.headers.containsKey('Range'), isFalse);
      expect(response.startOffsetBytes, 0);
      expect(response.statusCode, 200);
      // The response says what the gateway said about its encoding.
      expect(response.contentEncoding, 'gzip');
      expect(response.isContentEncoded, isTrue);
    });

    test('a resume is still a ranged request', () async {
      final tail = Uint8List.sublistView(script, 400);
      final harness = build((request) => http.StreamedResponse(
            Stream<List<int>>.fromIterable([tail]),
            206,
            headers: {
              'content-range': 'bytes 400-${script.length - 1}/${script.length}'
            },
          ));

      final response =
          await harness.source.open(txId: txId, startOffsetBytes: 400);

      expect(harness.client.requests.single.headers['Range'], 'bytes=400-');
      expect(response.startOffsetBytes, 400);
      expect(response.isContentEncoded, isFalse);
    });

    test('a gateway that answers 200 to a plain GET starts at byte 0',
        () async {
      final harness = build((request) => http.StreamedResponse(
            Stream<List<int>>.fromIterable([script]),
            200,
          ));

      final response = await harness.source.open(txId: txId);

      expect(response.startOffsetBytes, 0);
      expect(response.contentEncoding, isNull);
    });
  });

  group('R2: gzip that was not decoded is never saved as the file', () {
    test('gzip bytes for a script are reported', () async {
      final source = FakeDownloadSource(gzipped);
      final harness = build(source);

      final errors =
          await download(harness.downloader, fileSize: script.length);

      expect(errors.whereType<DownloadNotDecodedException>(), hasLength(1));
      // Not mistaken for a broken connection and asked for again.
      expect(source.requestedOffsets, [0]);
    });

    test('a real .gz file is saved as it is', () async {
      final source = FakeDownloadSource(gzipped);
      final harness = build(source);

      final errors = await download(
        harness.downloader,
        fileSize: gzipped.length,
        name: 'archive.gz',
        contentType: 'application/gzip',
      );

      expect(errors, isEmpty);
      expect(harness.io.savedBytes, gzipped);
    });

    test('a file of another type that is a gzip, with its right size, is saved',
        () async {
      final source = FakeDownloadSource(gzipped);
      final harness = build(source);

      final errors = await download(
        harness.downloader,
        fileSize: gzipped.length,
        name: 'logo.svgz',
        contentType: 'image/svg+xml',
      );

      expect(errors, isEmpty);
      expect(harness.io.savedBytes, gzipped);
    });

    test('a gzip type with the wrong size is not blamed on decoding', () async {
      final source = FakeDownloadSource(gzipped);
      final harness = build(source);

      final errors = await download(
        harness.downloader,
        fileSize: gzipped.length + 10,
        name: 'archive.gz',
        contentType: 'application/gzip',
      );

      expect(errors, isEmpty);
    });

    test('an ordinary file is untouched', () async {
      final source = FakeDownloadSource(script);
      final harness = build(source);

      expect(
          await download(harness.downloader, fileSize: script.length), isEmpty);
      expect(harness.io.savedBytes, script);
    });
  });
}

/// A gateway that drops the first connection, and whose second answer
/// declares a Content-Encoding the first did not.
class _EncodingOnSecondOpen extends FakeDownloadSource {
  _EncodingOnSecondOpen(super.body, {super.onOpen})
      : super(failAfterBytesOnFirstOpen: 400);

  int _calls = 0;

  @override
  Future<DownloadSourceResponse> open({
    required String txId,
    int startOffsetBytes = 0,
    bool verifyDownload = false,
  }) async {
    _calls++;
    final response = await super.open(
      txId: txId,
      startOffsetBytes: startOffsetBytes,
      verifyDownload: verifyDownload,
    );
    if (_calls == 1) return response;
    return DownloadSourceResponse(
      stream: response.stream,
      startOffsetBytes: response.startOffsetBytes,
      statusCode: response.statusCode,
      contentEncoding: 'gzip',
      cancel: response.cancel,
    );
  }
}
