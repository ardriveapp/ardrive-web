import 'dart:typed_data';

import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/mocks.dart';
import 'download_test_harness.dart';

/// F24: on web, *no* private download was authenticated at any size, because
/// both ciphers were routed into the streaming decryptor and its AES-GCM branch
/// trims the 16 byte tag without ever checking it.
///
/// These tests pin the replacement: one buffered, MAC-verified path for every
/// platform, and nothing on disk until the tag has passed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const txId = 'gcm-tx-id';
  const fileName = 'quarterly.pdf';
  final lastModified = DateTime.utc(2026, 8, 5);

  final plaintext = pseudoRandomBytes(40 * 1024, seed: 5);

  late Uint8List ciphertextWithMac;
  late String cipherIvString;
  late SecretKey fileKey;

  setUpAll(() async {
    final aesGcm = AesGcm.with256bits();
    fileKey = await aesGcm.newSecretKey();
    final nonce = aesGcm.newNonce();

    final secretBox = await aesGcm.encrypt(
      plaintext,
      secretKey: fileKey,
      nonce: nonce,
    );

    // The uploader stores ciphertext ++ MAC and publishes the nonce as a tag.
    ciphertextWithMac = Uint8List.fromList([
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
    cipherIvString = encodeBytesToBase64(Uint8List.fromList(nonce));
  });

  ({
    ArDriveDownloader downloader,
    RecordingArDriveIO io,
    FakeDownloadSource source,
  }) build(Uint8List body) {
    final io = RecordingArDriveIO();
    final source = FakeDownloadSource(body);

    return (
      downloader: ArDriveDownloader(
        ioFileAdapter: IOFileAdapter(),
        ardriveIo: io,
        arweave: MockArweaveService(),
        source: source,
      ),
      io: io,
      source: source,
    );
  }

  Future<List<Object>> download(ArDriveDownloader downloader) async {
    final progress = await downloader.downloadFile(
      txId: txId,
      fileSize: plaintext.length,
      fileName: fileName,
      lastModifiedDate: lastModified,
      contentType: 'application/pdf',
      isManifest: false,
      fileKey: fileKey,
      cipher: Cipher.aes256gcm,
      cipherIvString: cipherIvString,
    );

    return drainProgress(progress);
  }

  test('an intact AES-GCM file is authenticated and then saved', () async {
    final harness = build(ciphertextWithMac);

    final errors = await download(harness.downloader);

    expect(errors, isEmpty);
    expect(harness.io.savedBytes, plaintext);

    final verdict = await harness.downloader.integrity;
    expect(verdict.verdict, DataItemIntegrityVerdict.verified);
    expect(verdict.bytesHashed, plaintext.length);
  });

  test('tampered AES-GCM ciphertext fails authentication and nothing is '
      'written', () async {
    final tampered = Uint8List.fromList(ciphertextWithMac);
    // One flipped bit anywhere in the ciphertext invalidates the tag.
    tampered[1234] ^= 0x01;

    final harness = build(tampered);

    final errors = await download(harness.downloader);

    expect(errors, isNotEmpty);
    expect(errors.first, isA<DownloadIntegrityException>());
    expect(
      (errors.first as DownloadIntegrityException).txId,
      txId,
    );

    // The whole point: the saver was never even called.
    expect(harness.io.saveFileStreamCalls, 0);
    expect(harness.io.saveFileCalls, 0);
    expect(harness.io.savedBytes, isEmpty);

    final verdict = await harness.downloader.integrity;
    expect(verdict.verdict, DataItemIntegrityVerdict.failed);
  });

  test('a truncated MAC fails authentication rather than decrypting anyway',
      () async {
    final truncated = Uint8List.sublistView(
      ciphertextWithMac,
      0,
      ciphertextWithMac.length - 4,
    );

    final harness = build(Uint8List.fromList(truncated));

    final errors = await download(harness.downloader);

    expect(errors.whereType<DownloadIntegrityException>(), isNotEmpty);
    expect(harness.io.saveFileStreamCalls, 0);
    expect(harness.io.savedBytes, isEmpty);
  });

  test('downloadToMemory authenticates AES-GCM too, so thumbnails and previews '
      'are covered', () async {
    final harness = build(ciphertextWithMac);

    final bytes = await harness.downloader.downloadToMemory(
      txId: txId,
      fileSize: plaintext.length,
      fileName: fileName,
      lastModifiedDate: lastModified,
      contentType: 'application/pdf',
      isManifest: false,
      fileKey: fileKey,
      cipher: Cipher.aes256gcm,
      cipherIvString: cipherIvString,
    );

    expect(bytes, plaintext);
    expect((await harness.downloader.integrity).isVerified, isTrue);

    final tampered = Uint8List.fromList(ciphertextWithMac);
    tampered[10] ^= 0xff;
    final tamperedHarness = build(tampered);

    await expectLater(
      tamperedHarness.downloader.downloadToMemory(
        txId: txId,
        fileSize: plaintext.length,
        fileName: fileName,
        lastModifiedDate: lastModified,
        contentType: 'application/pdf',
        isManifest: false,
        fileKey: fileKey,
        cipher: Cipher.aes256gcm,
        cipherIvString: cipherIvString,
      ),
      throwsA(isA<DownloadIntegrityException>()),
    );
  });

  group('AesGcmStream is gone from the download path', () {
    test('constructing a downloader disarms unauthenticated GCM streaming',
        () async {
      build(ciphertextWithMac);

      expect(AesGcmStream.allowUnauthenticatedGcmDecryption, isFalse);

      // Anything that still reached for the streaming decryptor would now
      // throw instead of quietly returning unverified plaintext.
      await expectLater(
        Future.sync(() => AesGcmStream.unauthenticated(Uint8List(32))),
        throwsA(isA<StateError>()),
      );
    });

    test('a GCM download still succeeds with the kill switch off, which it '
        'could not do if it went through AesGcmStream', () async {
      final harness = build(ciphertextWithMac);

      expect(AesGcmStream.allowUnauthenticatedGcmDecryption, isFalse);

      final errors = await download(harness.downloader);

      expect(errors, isEmpty);
      expect(harness.io.savedBytes, plaintext);
    });

  });

  test('a file too large for the buffered path is refused, not streamed',
      () async {
    final harness = build(ciphertextWithMac);

    final progress = await harness.downloader.downloadFile(
      txId: txId,
      // Larger than any file the uploader would have encrypted with AES-GCM.
      fileSize: const MiB(200).size,
      fileName: fileName,
      lastModifiedDate: lastModified,
      contentType: 'application/pdf',
      isManifest: false,
      fileKey: fileKey,
      cipher: Cipher.aes256gcm,
      cipherIvString: cipherIvString,
    );

    final errors = await drainProgress(progress);

    expect(errors.whereType<DownloadTooLargeToAuthenticateException>(),
        isNotEmpty);
    expect(harness.io.saveFileStreamCalls, 0);
  });
}
