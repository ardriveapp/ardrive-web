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
/// platform, and no plaintext on disk until the tag has passed.
///
/// The web adds a wrinkle to *when*, not to what is verified — see the
/// `on the web` group.
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

  // Chrome only allows `window.showSaveFilePicker` while the click that led to
  // it is still *transient user activation*, which expires seconds after the
  // gesture. Buffering the whole ciphertext and asking afterwards means the
  // picker is refused at the end of a complete, verified download — for every
  // private file under the buffer cap, which is very nearly all of them. So on
  // the web the saver is called first and the download runs inside the stream
  // it reads.
  group('on the web the save target is opened before the download', () {
    const downloadOpened = 'opened the download';

    ({
      ArDriveDownloader downloader,
      WebShapedArDriveIO io,
      List<String> log,
    }) buildWeb(Uint8List body) {
      final log = <String>[];
      final io = WebShapedArDriveIO(log);

      return (
        downloader: ArDriveDownloader(
          ioFileAdapter: IOFileAdapter(),
          ardriveIo: io,
          arweave: MockArweaveService(),
          source: FakeDownloadSource(
            body,
            onOpen: () => log.add(downloadOpened),
          ),
          saveTargetNeedsUserActivation: true,
        ),
        io: io,
        log: log,
      );
    }

    test('the picker opens before a byte is fetched, and the bytes that '
        'follow are still verified', () async {
      final harness = buildWeb(ciphertextWithMac);

      final errors = await download(harness.downloader);

      expect(errors, isEmpty);
      expect(
        harness.log.take(2),
        [WebShapedArDriveIO.openedSaveTarget, downloadOpened],
        reason: 'the picker has to run while the click is still fresh',
      );
      expect(harness.io.fileOnDisk, plaintext);
      expect((await harness.downloader.integrity).isVerified, isTrue);
    });

    test('a tampered file leaves an empty file where the user chose to save, '
        'never plaintext', () async {
      final tampered = Uint8List.fromList(ciphertextWithMac);
      tampered[1234] ^= 0x01;

      final harness = buildWeb(tampered);

      final errors = await download(harness.downloader);

      expect(errors.whereType<DownloadIntegrityException>(), isNotEmpty);

      // The price of opening the picker while the click is still fresh: the
      // saver *was* called, and the file the picker created is still there.
      // It never received a byte, and web_io's failure path does not remove
      // it.
      expect(harness.io.saveFileStreamCalls, 1);
      expect(
        harness.log,
        [WebShapedArDriveIO.openedSaveTarget, downloadOpened],
      );
      expect(harness.io.fileOnDisk, isEmpty);

      expect(
        (await harness.downloader.integrity).verdict,
        DataItemIntegrityVerdict.failed,
      );
    });

    test('progress still only goes up, though the save starts first', () async {
      final harness = buildWeb(ciphertextWithMac);

      final progress = await harness.downloader.downloadFile(
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

      final values = <double>[];
      await progress.forEach(values.add);

      expect(values, isNotEmpty);
      expect(values.last, 100);

      for (var i = 1; i < values.length; i++) {
        expect(
          values[i],
          greaterThanOrEqualTo(values[i - 1]),
          reason: 'the save reports 0% before the download has even started, '
              'so it must not count until there is something to save',
        );
      }
    });
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

    // Off the web nothing is racing a user gesture, so the strongest form of
    // the guarantee holds: the saver was never even called.
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

  // A file larger than DownloadPolicy.maxBufferedCiphertextBytes cannot have
  // its MAC checked — there is nowhere to hold it. Refusing it outright is not
  // an option either: AES-GCM was ArDrive's only symmetric cipher for years
  // and ardrive-cli still writes it at any size, so the refusal broke large
  // legacy private files that used to download fine.
  //
  // The answer is the one AES-CTR has always given: stream it, and say plainly
  // that nothing vouched for the bytes.
  group('an AES-GCM file too large to buffer', () {
    // What the decryptor was told. The declared file size is 200 MiB while the
    // body is small, which is what lets a unit test reach the branch at all.
    late List<bool> oversizedFlags;

    Future<Stream<Uint8List>> recordingDecryptor(
      String cipher,
      Uint8List cipherIv,
      Stream<Uint8List> ciphertextStream,
      Uint8List keyData,
      int fileSize, {
      int startOffsetBytes = 0,
      bool gcmTooLargeToBuffer = false,
    }) {
      oversizedFlags.add(gcmTooLargeToBuffer);

      return positionalXorDecryptor(
        cipher,
        cipherIv,
        ciphertextStream,
        keyData,
        fileSize,
        startOffsetBytes: startOffsetBytes,
        gcmTooLargeToBuffer: gcmTooLargeToBuffer,
      );
    }

    final body = pseudoRandomBytes(4096, seed: 21);
    final oversizedFileSize = const MiB(200).size;

    setUp(() => oversizedFlags = []);

    ({ArDriveDownloader downloader, RecordingArDriveIO io}) buildStreaming() {
      final io = RecordingArDriveIO();

      return (
        downloader: ArDriveDownloader(
          ioFileAdapter: IOFileAdapter(),
          ardriveIo: io,
          arweave: MockArweaveService(),
          source: FakeDownloadSource(body),
          decryptStream: recordingDecryptor,
          verifierFactory: (id) async =>
              StreamedDataItemVerifier.unavailable('not under test'),
        ),
        io: io,
      );
    }

    test('downloads by streaming instead of being refused', () async {
      final harness = buildStreaming();

      final progress = await harness.downloader.downloadFile(
        txId: txId,
        fileSize: oversizedFileSize,
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
          isEmpty);
      expect(errors, isEmpty);
      expect(harness.io.savedBytes, positionalXorPlaintext(body));
      expect(harness.io.saveFileStreamCalls, 1);
    });

    test('asks for the unauthenticated decryptor explicitly', () async {
      final harness = buildStreaming();

      await drainProgress(await harness.downloader.downloadFile(
        txId: txId,
        fileSize: oversizedFileSize,
        fileName: fileName,
        lastModifiedDate: lastModified,
        contentType: 'application/pdf',
        isManifest: false,
        fileKey: fileKey,
        cipher: Cipher.aes256gcm,
        cipherIvString: cipherIvString,
      ));

      expect(oversizedFlags, [true]);
    });

    test('reports notVerified, and says why', () async {
      final harness = buildStreaming();

      await drainProgress(await harness.downloader.downloadFile(
        txId: txId,
        fileSize: oversizedFileSize,
        fileName: fileName,
        lastModifiedDate: lastModified,
        contentType: 'application/pdf',
        isManifest: false,
        fileKey: fileKey,
        cipher: Cipher.aes256gcm,
        cipherIvString: cipherIvString,
      ));

      final verdict = await harness.downloader.integrity;

      expect(verdict.verdict, DataItemIntegrityVerdict.notVerified);
      expect(verdict.isVerified, isFalse);
      expect(verdict.reason, contains('authentication tag could not be'));
    });

    test('a file that fits is never routed here, whatever else changes',
        () async {
      // The streaming decryptor throws if it is reached at all: under the cap
      // there is no legitimate way to it.
      final io = RecordingArDriveIO();
      final downloader = ArDriveDownloader(
        ioFileAdapter: IOFileAdapter(),
        ardriveIo: io,
        arweave: MockArweaveService(),
        source: FakeDownloadSource(ciphertextWithMac),
        decryptStream: (a, b, c, d, e,
                {int startOffsetBytes = 0,
                bool gcmTooLargeToBuffer = false}) =>
            throw StateError('a GCM file under the cap must be MAC-verified'),
      );

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

      expect(await drainProgress(progress), isEmpty);
      expect(io.savedBytes, plaintext);
      expect((await downloader.integrity).isVerified, isTrue);
    });
  });

}
