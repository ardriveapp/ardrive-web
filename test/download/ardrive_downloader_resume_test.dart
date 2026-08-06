import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/mocks.dart';
import 'download_test_harness.dart';

/// §3.2/§3.4: the AES-CTR and public streaming path — resume from an aligned
/// offset, refuse to splice a gateway that ignored `Range`, and report an
/// honest integrity verdict without ever holding up the save.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A real-shaped (43 character, base64url) transaction id, so the integrity
  // verifier gets as far as it can before it runs out of a real signature.
  const txId = 'nS7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWeR';
  const fileName = 'big.mp4';
  final lastModified = DateTime.utc(2026, 8, 5);

  // Deliberately not a multiple of the AES block, and interrupted at a byte
  // that is not either, so alignment has to do real work.
  const fileSize = 5003;
  const interruptAt = 1234;
  const alignedResumeOffset = 1232; // 1234 rounded down to a 16 byte block

  final ciphertext = pseudoRandomBytes(fileSize, seed: 11);
  final expectedPlaintext = positionalXorPlaintext(ciphertext);

  final fileKey = SecretKey(List<int>.filled(32, 7));
  final cipherIvString = encodeBytesToBase64(Uint8List(12));

  ({
    ArDriveDownloader downloader,
    RecordingArDriveIO io,
  }) build(
    FakeDownloadSource source, {
    IntegrityVerifierFactory? verifierFactory,
  }) {
    final io = RecordingArDriveIO();

    return (
      downloader: ArDriveDownloader(
        ioFileAdapter: IOFileAdapter(),
        ardriveIo: io,
        arweave: MockArweaveService(),
        source: source,
        decryptStream: positionalXorDecryptor,
        verifierFactory: verifierFactory ??
            ((id) async =>
                StreamedDataItemVerifier.unavailable('not under test')),
      ),
      io: io,
    );
  }

  Future<List<Object>> downloadPrivate(
    ArDriveDownloader downloader, {
    bool verifyDownload = false,
  }) async {
    final progress = await downloader.downloadFile(
      txId: txId,
      fileSize: fileSize,
      fileName: fileName,
      lastModifiedDate: lastModified,
      contentType: 'video/mp4',
      isManifest: false,
      fileKey: fileKey,
      cipher: Cipher.aes256ctr,
      cipherIvString: cipherIvString,
      verifyDownload: verifyDownload,
    );

    return drainProgress(progress);
  }

  group('resume offsets', () {
    test('encrypted streams align down to the AES block, plain ones do not',
        () {
      expect(resumeOffsetFor(1234, encrypted: true), 1232);
      expect(resumeOffsetFor(1234, encrypted: false), 1234);
      expect(resumeOffsetFor(0, encrypted: true), 0);
      expect(resumeOffsetFor(16, encrypted: true), 16);
      expect(resumeOffsetFor(31, encrypted: true), 16);

      // At most one block is ever re-fetched: not one 256 KiB chunk.
      for (var delivered = 0; delivered < 1024; delivered++) {
        final offset = resumeOffsetFor(delivered, encrypted: true);
        expect(delivered - offset, lessThan(AesStream.blockLengthBytes));
      }
    });
  });

  group('AES-CTR resume', () {
    test('an interrupted download resumes from the aligned offset and is '
        'byte identical to an uninterrupted one', () async {
      final uninterruptedSource = FakeDownloadSource(ciphertext);
      final uninterrupted = build(uninterruptedSource);
      expect(await downloadPrivate(uninterrupted.downloader), isEmpty);

      final resumingSource = FakeDownloadSource(
        ciphertext,
        failAfterBytesOnFirstOpen: interruptAt,
      );
      final resuming = build(resumingSource);
      expect(await downloadPrivate(resuming.downloader), isEmpty);

      expect(uninterrupted.io.savedBytes, expectedPlaintext);
      expect(resuming.io.savedBytes, uninterrupted.io.savedBytes);
      expect(resuming.io.savedBytes.length, fileSize);

      // It asked for the block-aligned offset, not the raw one, and not zero.
      expect(resumingSource.requestedOffsets, [0, alignedResumeOffset]);
    });

    test('the overlap is dropped rather than written twice, at every '
        'misalignment', () async {
      for (final interruption in [16, 17, 31, 255, 4097, fileSize - 1]) {
        final source = FakeDownloadSource(
          ciphertext,
          failAfterBytesOnFirstOpen: interruption,
          chunkSize: 64,
        );
        final harness = build(source);

        expect(await downloadPrivate(harness.downloader), isEmpty,
            reason: 'interrupted at $interruption');
        expect(harness.io.savedBytes, expectedPlaintext,
            reason: 'interrupted at $interruption');
        expect(
          source.requestedOffsets.last,
          AesStream.alignStartOffsetDown(interruption),
          reason: 'interrupted at $interruption',
        );
      }
    });

    test('a public download resumes at the exact byte, with no cipher '
        'alignment', () async {
      final source = FakeDownloadSource(
        ciphertext,
        failAfterBytesOnFirstOpen: interruptAt,
      );
      final harness = build(source);

      final progress = await harness.downloader.downloadFile(
        txId: txId,
        fileSize: fileSize,
        fileName: fileName,
        lastModifiedDate: lastModified,
        contentType: 'video/mp4',
        isManifest: false,
      );

      expect(await drainProgress(progress), isEmpty);
      expect(harness.io.savedBytes, ciphertext);
      expect(source.requestedOffsets, [0, interruptAt]);
    });

    test('a download that fails before delivering a byte is not resumed',
        () async {
      final source = FakeDownloadSource(
        ciphertext,
        failAfterBytesOnFirstOpen: 0,
      );
      final harness = build(source);

      final errors = await downloadPrivate(harness.downloader);

      expect(errors, isNotEmpty);
      expect(source.requestedOffsets, [0]);
    });

    test('a chunk-verified (L1) download restarts instead of resuming, so the '
        'verification it asked for is never quietly dropped', () async {
      final source = FakeDownloadSource(
        ciphertext,
        failAfterBytesOnFirstOpen: interruptAt,
      );
      final harness = build(source);

      final errors =
          await downloadPrivate(harness.downloader, verifyDownload: true);

      expect(errors.whereType<DownloadResumeNotSupportedException>(),
          isNotEmpty);
      expect(source.requestedOffsets, [0]);
      expect(source.verifyDownloadFlags, [true]);
    });
  });

  group('a gateway that ignores Range', () {
    test('answering 200 to a Range request restarts instead of splicing '
        'corrupt bytes', () async {
      final source = FakeDownloadSource(
        ciphertext,
        failAfterBytesOnFirstOpen: interruptAt,
        honorsRange: false,
      );
      final harness = build(source);

      final errors = await downloadPrivate(harness.downloader);

      final refusals =
          errors.whereType<DownloadResumeNotSupportedException>().toList();
      expect(refusals, isNotEmpty);
      expect(refusals.first.requestedOffset, alignedResumeOffset);
      expect(refusals.first.statusCode, 200);

      // Nothing from the second, full-body response was appended: what is on
      // disk is a clean prefix of the file, which a restart replaces.
      expect(harness.io.savedBytes.length, interruptAt);
      expect(
        harness.io.savedBytes,
        Uint8List.sublistView(expectedPlaintext, 0, interruptAt),
      );
      expect(source.cancelCount, greaterThan(0));
    });

    test('the status, not the request, decides where the body starts', () {
      // turbo-gateway.com: honours the range.
      expect(
        GatewayDownloadSource.startOffsetFromResponse(1232, 206, null),
        1232,
      );
      expect(
        GatewayDownloadSource.startOffsetFromResponse(
            1232, 206, 'bytes 1232-5002/5003'),
        1232,
      );

      // arweave.net: ignores the header and returns the whole body.
      expect(GatewayDownloadSource.startOffsetFromResponse(1232, 200, null), 0);
      expect(
        GatewayDownloadSource.startOffsetFromResponse(
            1232, 200, 'bytes 1232-5002/5003'),
        0,
      );

      // A 206 that serves a different range than asked for is caught by the
      // caller's offset comparison rather than spliced.
      expect(
        GatewayDownloadSource.startOffsetFromResponse(
            1232, 206, 'bytes 0-5002/5003'),
        0,
      );

      expect(GatewayDownloadSource.startOffsetFromResponse(0, 200, null), 0);
    });
  });

  group('with the production AES-CTR decryptor', () {
    // The offset threading is proved everywhere by the stand-in decryptor
    // above; this closes the loop on the real one wherever the WebCrypto
    // native library can actually be loaded.
    final realKey =
        Uint8List.fromList(List<int>.generate(32, (i) => (i * 7 + 11) & 0xff));

    late bool webCryptoAvailable;

    setUpAll(() async {
      try {
        final aesCtr = await AesCtrStream.fromKeyData(realKey);

        // `importRawKey` never touches BoringSSL, so it succeeds even where
        // the native library cannot be loaded and the probe would report a
        // false positive. Run a real encryption - generating the nonce calls
        // `fillRandomBytes`, which is what triggers the lookup.
        final encrypted = await aesCtr.encryptStream(
          Stream.value(Uint8List.fromList(const [0])),
          1,
        );
        await encrypted.stream.drain<void>();

        webCryptoAvailable = true;
      } catch (_) {
        webCryptoAvailable = false;
      }
    });

    test('an interrupted download is byte identical to an uninterrupted one',
        () async {
      if (!webCryptoAvailable) {
        markTestSkipped('WebCrypto is not loadable in this environment');
        return;
      }

      final plaintext = pseudoRandomBytes(fileSize, seed: 3);

      final aesCtr = await AesCtrStream.fromKeyData(realKey);
      final encrypted =
          await aesCtr.encryptStream(Stream.value(plaintext), fileSize);
      final realCiphertext = await concatenate(encrypted.stream);
      final realIv = encodeBytesToBase64(encrypted.nonce);

      final source = FakeDownloadSource(
        realCiphertext,
        failAfterBytesOnFirstOpen: interruptAt,
      );
      final io = RecordingArDriveIO();

      // No decryptStream override: this is decryptTransactionDataStream.
      final downloader = ArDriveDownloader(
        ioFileAdapter: IOFileAdapter(),
        ardriveIo: io,
        arweave: MockArweaveService(),
        source: source,
        verifierFactory: (id) async =>
            StreamedDataItemVerifier.unavailable('not under test'),
      );

      final progress = await downloader.downloadFile(
        txId: txId,
        fileSize: fileSize,
        fileName: fileName,
        lastModifiedDate: lastModified,
        contentType: 'video/mp4',
        isManifest: false,
        fileKey: SecretKey(realKey),
        cipher: Cipher.aes256ctr,
        cipherIvString: realIv,
      );

      expect(await drainProgress(progress), isEmpty);
      expect(io.savedBytes, plaintext);
      expect(source.requestedOffsets, [0, alignedResumeOffset]);
    });
  });

  group('integrity verdicts', () {
    test('an uninterrupted download hashes every ciphertext byte', () async {
      final harness = build(
        FakeDownloadSource(ciphertext),
        verifierFactory: (id) async => realShapedVerifier(id),
      );

      expect(await downloadPrivate(harness.downloader), isEmpty);

      final verdict = await harness.downloader.integrity;

      // The verifier is fed the ciphertext - that is what was signed - so it
      // sees the whole file.
      expect(verdict.bytesHashed, fileSize);
      expect(verdict.reason ?? '', isNot(contains('Resumed')));
    });

    test('a resumed download reports notVerified rather than guessing',
        () async {
      final harness = build(
        FakeDownloadSource(
          ciphertext,
          failAfterBytesOnFirstOpen: interruptAt,
        ),
        verifierFactory: (id) async => realShapedVerifier(id),
      );

      expect(await downloadPrivate(harness.downloader), isEmpty);

      final verdict = await harness.downloader.integrity;

      expect(verdict.verdict, DataItemIntegrityVerdict.notVerified);
      expect(verdict.isFailed, isFalse, reason: 'a resume is not a corruption');
      expect(verdict.reason, contains('Resumed'));
      expect(verdict.bytesHashed, interruptAt);

      // ...and the file itself is still correct.
      expect(harness.io.savedBytes, expectedPlaintext);
    });

    test('the verdict never delays save completion', () async {
      final gate = Completer<void>();
      final harness = build(
        FakeDownloadSource(ciphertext),
        verifierFactory: (id) async => GatedVerifier(gate),
      );

      expect(await downloadPrivate(harness.downloader), isEmpty);
      expect(harness.io.savedBytes, expectedPlaintext);

      // Bound *after* the download, deliberately: `downloadFile` resets the
      // integrity completer as its first act, so a future taken beforehand
      // belongs to a completer the download then discards and would never
      // resolve. Reading it here is also the sharper assertion - the save has
      // already finished by this line, so a still-pending verdict is exactly
      // the guarantee under test.
      var verdictArrived = false;
      unawaited(harness.downloader.integrity.then((_) {
        verdictArrived = true;
      }));

      // Give any pending microtasks a chance: the save is done and the verdict
      // is still outstanding.
      await Future<void>.delayed(Duration.zero);
      expect(verdictArrived, isFalse);

      gate.complete();
      final verdict = await harness.downloader.integrity;

      expect(verdict.verdict, DataItemIntegrityVerdict.notVerified);
    });

    test('aborting a download settles the verdict instead of leaving it '
        'pending forever', () async {
      final harness = build(FakeDownloadSource(ciphertext));

      await harness.downloader.abortDownload();

      final verdict = await harness.downloader.integrity;
      expect(verdict.verdict, DataItemIntegrityVerdict.notVerified);
    });
  });
}
