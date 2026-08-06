import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/download/download_exceptions.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/utils.dart';

/// Deterministic pseudo-random bytes — the same input every run, so a byte
/// difference is always a real one.
Uint8List pseudoRandomBytes(int length, {int seed = 1}) {
  final random = math.Random(seed);
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}

Stream<List<int>> chunked(Uint8List data, int chunkSize) async* {
  for (var offset = 0; offset < data.length; offset += chunkSize) {
    final end = math.min(offset + chunkSize, data.length);
    yield Uint8List.sublistView(data, offset, end);
  }
}

/// Emits exactly [failAfterBytes] bytes of [data] and then fails, the way a
/// dropped connection does.
Stream<List<int>> chunkedThenFail(
  Uint8List data,
  int chunkSize,
  int failAfterBytes,
  String txId,
) async* {
  var emitted = 0;

  for (var offset = 0; offset < data.length; offset += chunkSize) {
    final end = math.min(offset + chunkSize, data.length);
    var chunk = Uint8List.sublistView(data, offset, end);

    if (emitted + chunk.length >= failAfterBytes) {
      chunk = Uint8List.sublistView(chunk, 0, failAfterBytes - emitted);
      if (chunk.isNotEmpty) yield chunk;
      throw DownloadNetworkException(txId, 'connection dropped');
    }

    yield chunk;
    emitted += chunk.length;
  }
}

/// A [DownloadSource] backed by a byte array, with a switch for the two
/// gateway behaviours measured on 2026-08-05: honouring `Range` with a `206`,
/// or ignoring it and answering `200` with the whole body.
class FakeDownloadSource implements DownloadSource {
  FakeDownloadSource(
    this.body, {
    this.failAfterBytesOnFirstOpen,
    this.honorsRange = true,
    this.chunkSize = 256,
  });

  final Uint8List body;

  /// Bytes to deliver on the first open before the connection drops.
  final int? failAfterBytesOnFirstOpen;

  /// `false` reproduces arweave.net: the `Range` header is ignored.
  final bool honorsRange;

  final int chunkSize;

  final List<int> requestedOffsets = [];
  final List<bool> verifyDownloadFlags = [];
  int cancelCount = 0;

  int _opens = 0;

  @override
  Future<DownloadSourceResponse> open({
    required String txId,
    int startOffsetBytes = 0,
    bool verifyDownload = false,
  }) async {
    requestedOffsets.add(startOffsetBytes);
    verifyDownloadFlags.add(verifyDownload);
    _opens++;

    if (startOffsetBytes > 0 && !honorsRange) {
      return DownloadSourceResponse(
        stream: chunked(body, chunkSize),
        startOffsetBytes: 0,
        statusCode: 200,
        cancel: () => cancelCount++,
      );
    }

    final tail = Uint8List.sublistView(body, startOffsetBytes);
    final failAfter = _opens == 1 ? failAfterBytesOnFirstOpen : null;

    return DownloadSourceResponse(
      stream: failAfter == null
          ? chunked(tail, chunkSize)
          : chunkedThenFail(tail, chunkSize, failAfter, txId),
      startOffsetBytes: startOffsetBytes,
      statusCode: startOffsetBytes == 0 ? 200 : 206,
      cancel: () => cancelCount++,
    );
  }
}

/// Records what would have been written to disk.
class RecordingArDriveIO implements ArDriveIO {
  final BytesBuilder saved = BytesBuilder(copy: false);

  int saveFileStreamCalls = 0;
  int saveFileCalls = 0;

  Uint8List get savedBytes => Uint8List.fromList(saved.toBytes());

  @override
  Future<void> saveFile(IOFile file) async {
    saveFileCalls++;
    saved.add(await file.readAsBytes());
  }

  @override
  Stream<SaveStatus> saveFileStream(
      IOFile file, Completer<bool> finalize) async* {
    saveFileStreamCalls++;

    final totalBytes = await file.length;
    var bytesSaved = 0;

    yield SaveStatus(bytesSaved: bytesSaved, totalBytes: totalBytes);

    await for (final chunk in file.openReadStream()) {
      saved.add(chunk);
      bytesSaved += chunk.length;
      yield SaveStatus(bytesSaved: bytesSaved, totalBytes: totalBytes);
    }

    if (!finalize.isCompleted) finalize.complete(true);

    yield SaveStatus(
      bytesSaved: bytesSaved,
      totalBytes: totalBytes,
      saveResult: await finalize.future,
    );
  }

  @override
  Future<IOFile> pickFile({
    List<String>? allowedExtensions,
    required FileSource fileSource,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<IOFile>> pickFiles({
    List<String>? allowedExtensions,
    required FileSource fileSource,
  }) =>
      throw UnimplementedError();

  @override
  Future<IOFolder> pickFolder() => throw UnimplementedError();
}

/// A stand-in for AES-CTR: length preserving and, crucially, a pure function of
/// the *absolute* byte position. A resume that passes the wrong
/// `startOffsetBytes` produces wrong plaintext, so the byte-identity assertions
/// really do test the offset threading — and, unlike WebCrypto, this runs
/// anywhere `flutter test` does.
Future<Stream<Uint8List>> positionalXorDecryptor(
  String cipher,
  Uint8List cipherIv,
  Stream<Uint8List> ciphertextStream,
  Uint8List keyData,
  int fileSize, {
  int startOffsetBytes = 0,
}) async {
  var position = startOffsetBytes;

  return ciphertextStream.map((chunk) {
    final out = Uint8List(chunk.length);
    for (var i = 0; i < chunk.length; i++) {
      out[i] = chunk[i] ^ keystreamByte(position + i);
    }
    position += chunk.length;
    return out;
  });
}

int keystreamByte(int position) => (position * 31 + 7) & 0xff;

/// What [positionalXorDecryptor] turns [ciphertext] into.
Uint8List positionalXorPlaintext(Uint8List ciphertext) {
  final out = Uint8List(ciphertext.length);
  for (var i = 0; i < ciphertext.length; i++) {
    out[i] = ciphertext[i] ^ keystreamByte(i);
  }
  return out;
}

/// A verifier that can reach a verdict on its own, so that
/// [StreamedDataItemVerifier.markUnverifiable] on resume is observably
/// different from "there was nothing to check".
///
/// The owner and signature are the right *length* for an Arweave data item —
/// enough to get past the "unsupported signature type" early exit — but they
/// are not a real signature, so an untouched run reports [verdict] `failed` or
/// `notVerified` while still hashing every byte that streamed through.
StreamedDataItemVerifier realShapedVerifier(String txId) {
  final base64Zeros = encodeBytesToBase64(Uint8List(512));

  return StreamedDataItemVerifier(
    dataItemId: txId,
    owner: base64Zeros,
    signature: base64Zeros,
    anchor: '',
    target: '',
    tags: const [DataItemTag('Cipher', 'AES256-CTR')],
  );
}

/// A verifier whose verdict is held back until [gate] is completed, so a test
/// can prove that saving does not wait for it.
class GatedVerifier extends StreamedDataItemVerifier {
  GatedVerifier(this.gate) : super.unavailable('gated for the test');

  final Completer<void> gate;

  @override
  Future<DataItemIntegrityResult> finish() async {
    await gate.future;
    return super.finish();
  }
}

/// Collects a byte stream into one buffer.
Future<Uint8List> concatenate(Stream<Uint8List> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

/// Drains a download's progress stream, returning every error it emitted.
Future<List<Object>> drainProgress(Stream<double> progress) {
  final errors = <Object>[];
  final done = Completer<List<Object>>();

  progress.listen(
    (_) {},
    onError: errors.add,
    onDone: () => done.complete(errors),
    cancelOnError: false,
  );

  return done.future;
}
