import 'dart:typed_data';

import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/download/download_exceptions.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/mocks.dart';
import 'download_test_harness.dart';

/// Who settles the `finalize` completer, and what the user is told when the
/// gateway — rather than the user — ends a download.
///
/// Every test here saves through [MobileShapedArDriveIO], which reproduces
/// `DartIOFileSaver`'s real behaviour: it never completes `finalize` itself,
/// it deletes the finished file if the answer is `false`, and it turns a
/// broken download into `saveResult: false`. Running these against
/// [RecordingArDriveIO] would prove nothing — it answers `finalize` on the
/// downloader's behalf, which is precisely how the mobile hang stayed
/// invisible.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const txId = 'nS7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWeR';
  const fileName = 'holiday.mp4';
  final lastModified = DateTime.utc(2026, 8, 5);

  const fileSize = 5003;
  final ciphertext = pseudoRandomBytes(fileSize, seed: 11);
  final expectedPlaintext = positionalXorPlaintext(ciphertext);

  final ctrKey = SecretKey(List<int>.filled(32, 7));
  final cipherIvString = encodeBytesToBase64(Uint8List(12));

  ArDriveDownloader build(
    DownloadSource source,
    ArDriveIO io, {
    Duration? resumeBackoffStep,
  }) =>
      ArDriveDownloader(
        ioFileAdapter: IOFileAdapter(),
        ardriveIo: io,
        arweave: MockArweaveService(),
        source: source,
        decryptStream: positionalXorDecryptor,
        verifierFactory: (id) async =>
            StreamedDataItemVerifier.unavailable('not under test'),
        resumeBackoffStep: resumeBackoffStep,
      );

  Future<Stream<double>> downloadPrivateCtr(ArDriveDownloader downloader) =>
      downloader.downloadFile(
        txId: txId,
        fileSize: fileSize,
        fileName: fileName,
        lastModifiedDate: lastModified,
        contentType: 'video/mp4',
        isManifest: false,
        fileKey: ctrKey,
        cipher: Cipher.aes256ctr,
        cipherIvString: cipherIvString,
      );

  group('a saver that waits for the downloader to settle finalize', () {
    test('an AES-CTR download completes instead of hanging at 100%', () async {
      final io = MobileShapedArDriveIO();
      final downloader = build(FakeDownloadSource(ciphertext), io);

      // Nobody cancels, and nobody but the downloader can answer `finalize`.
      // Before the fix this future never completed.
      final errors = await drainProgress(await downloadPrivateCtr(downloader))
          .timeout(const Duration(seconds: 10));

      expect(errors, isEmpty);
      expect(io.savedBytes, expectedPlaintext);
      expect(io.deleted, isFalse);
    });

    test('a buffered AES-GCM download completes too — the plaintext is already '
        'in memory, but it still goes out through the streaming saver',
        () async {
      final plaintext = pseudoRandomBytes(4096, seed: 5);

      final aesGcm = AesGcm.with256bits();
      final fileKey = await aesGcm.newSecretKey();
      final nonce = aesGcm.newNonce();
      final secretBox =
          await aesGcm.encrypt(plaintext, secretKey: fileKey, nonce: nonce);

      final io = MobileShapedArDriveIO();
      final downloader = build(
        FakeDownloadSource(Uint8List.fromList(
            [...secretBox.cipherText, ...secretBox.mac.bytes])),
        io,
      );

      final progress = await downloader.downloadFile(
        txId: txId,
        fileSize: plaintext.length,
        fileName: 'quarterly.pdf',
        lastModifiedDate: lastModified,
        contentType: 'application/pdf',
        isManifest: false,
        fileKey: fileKey,
        cipher: Cipher.aes256gcm,
        cipherIvString: encodeBytesToBase64(Uint8List.fromList(nonce)),
      );

      final errors =
          await drainProgress(progress).timeout(const Duration(seconds: 10));

      expect(errors, isEmpty);
      expect(io.savedBytes, plaintext);
      expect(io.deleted, isFalse);
    });

    test('a public download completes as well', () async {
      final io = MobileShapedArDriveIO();
      final downloader = build(FakeDownloadSource(ciphertext), io);

      final progress = await downloader.downloadFile(
        txId: txId,
        fileSize: fileSize,
        fileName: fileName,
        lastModifiedDate: lastModified,
        contentType: 'video/mp4',
        isManifest: false,
      );

      expect(await drainProgress(progress).timeout(const Duration(seconds: 10)),
          isEmpty);
      expect(io.savedBytes, ciphertext);
    });

    test('cancelling after the last byte was written keeps the finished file',
        () async {
      final io = MobileShapedArDriveIO();
      final downloader = build(FakeDownloadSource(ciphertext), io);

      expect(
        await drainProgress(await downloadPrivateCtr(downloader))
            .timeout(const Duration(seconds: 10)),
        isEmpty,
      );

      // The only way a user could unblock the old hang was to press Cancel,
      // which deleted the file they had just waited for.
      await downloader.abortDownload();

      expect(io.deleted, isFalse);
      expect(io.savedBytes, expectedPlaintext);
    });

    test('cancelling mid-download still throws away what was written',
        () async {
      final io = MobileShapedArDriveIO();
      final source = StallingDownloadSource(ciphertext);
      final downloader = build(source, io);

      final progress = await downloadPrivateCtr(downloader);
      final errors = drainProgress(progress);

      await source.delivering.future;
      await downloader.abortDownload();
      source.release.complete();

      expect(
        (await errors.timeout(const Duration(seconds: 10)))
            .whereType<DownloadCancelledException>(),
        isNotEmpty,
      );
      expect(io.deleted, isTrue);
      expect(io.savedBytes, isEmpty);
    });
  });

  group('a download the gateway ended is not reported as a cancellation', () {
    test('a 404 on every gateway throws out of downloadFile, before the user '
        'is asked where to save anything', () async {
      final io = MobileShapedArDriveIO();
      final downloader = build(
        FakeDownloadSource(
          ciphertext,
          errorOnOpen: const DownloadFileNotFoundException(txId),
        ),
        io,
      );

      await expectLater(
        downloadPrivateCtr(downloader),
        throwsA(isA<DownloadFileNotFoundException>()),
      );

      expect(io.saveFileStreamCalls, 0,
          reason: 'the save picker must not open for a download that cannot '
              'start');
    });

    test('a rate limit surfaces as itself', () async {
      final downloader = build(
        FakeDownloadSource(
          ciphertext,
          errorOnOpen: const DownloadRateLimitException(txId),
        ),
        MobileShapedArDriveIO(),
      );

      await expectLater(
        downloadPrivateCtr(downloader),
        throwsA(isA<DownloadRateLimitException>()),
      );
    });

    test('a mid-stream failure the resumes cannot recover from surfaces as the '
        'network error it is, not as DownloadCancelledException', () async {
      final io = MobileShapedArDriveIO();
      final downloader = build(
        // Every connection dies after a hundred bytes, so the retries run out
        // long before the file does.
        FakeDownloadSource(ciphertext, failAfterBytesOnEveryOpen: 100),
        io,
        resumeBackoffStep: Duration.zero,
      );

      final errors = await drainProgress(await downloadPrivateCtr(downloader))
          .timeout(const Duration(seconds: 10));

      expect(errors.whereType<DownloadNetworkException>(), isNotEmpty,
          reason: 'the saver swallowed it into saveResult: false; the '
              'downloader has to put the real cause back');
      expect(errors.whereType<DownloadCancelledException>(), isEmpty);
      expect(io.savedBytes.length, lessThan(fileSize),
          reason: 'the download never finished, whatever the saver reported');
    });

    test('the integrity verdict is settled, not left pending, when a gateway '
        'never answers', () async {
      final downloader = build(
        FakeDownloadSource(
          ciphertext,
          errorOnOpen: const DownloadNetworkException(txId, 'no route'),
        ),
        MobileShapedArDriveIO(),
      );

      await expectLater(
        downloadPrivateCtr(downloader),
        throwsA(isA<DownloadNetworkException>()),
      );

      final verdict =
          await downloader.integrity.timeout(const Duration(seconds: 10));
      expect(verdict.verdict, DataItemIntegrityVerdict.notVerified);
    });
  });

  group('the resume loop is bounded', () {
    test('a gateway that dribbles one byte per connection is given up on',
        () async {
      final io = MobileShapedArDriveIO();
      final source = FakeDownloadSource(
        ciphertext,
        // Every attempt makes *progress*, so the per-attempt budget is reset
        // every time: only the total ceiling can end this.
        failAfterBytesOnEveryOpen: 1,
      );
      final downloader = build(source, io, resumeBackoffStep: Duration.zero);

      final progress = await downloader.downloadFile(
        txId: txId,
        fileSize: fileSize,
        fileName: fileName,
        lastModifiedDate: lastModified,
        contentType: 'video/mp4',
        isManifest: false,
      );

      final errors =
          await drainProgress(progress).timeout(const Duration(seconds: 30));

      expect(errors, isNotEmpty);
      // Bounded, and bounded tightly: one initial open plus the ceiling.
      expect(source.requestedOffsets.length, lessThanOrEqualTo(16));
      expect(source.requestedOffsets.length, greaterThan(1),
          reason: 'progress should still buy retries, just not infinite ones');
      // Every reconnection did move forward by a byte, which is exactly what
      // defeats a consecutive-failure budget on its own.
      expect(source.requestedOffsets.first, 0);
      expect(source.requestedOffsets.last, source.requestedOffsets.length - 1);
      expect(io.savedBytes.length, source.requestedOffsets.length);
    });

    test('resumes wait before reconnecting', () async {
      final io = MobileShapedArDriveIO();
      final source = FakeDownloadSource(
        ciphertext,
        failAfterBytesOnFirstOpen: 1024,
      );
      final downloader = build(
        source,
        io,
        resumeBackoffStep: const Duration(milliseconds: 120),
      );

      final stopwatch = Stopwatch()..start();
      final errors = await drainProgress(await downloadPrivateCtr(downloader))
          .timeout(const Duration(seconds: 10));
      stopwatch.stop();

      expect(errors, isEmpty);
      expect(io.savedBytes, expectedPlaintext);
      expect(stopwatch.elapsed,
          greaterThanOrEqualTo(const Duration(milliseconds: 100)));
    });
  });
}
