import 'dart:async';

import 'package:ardrive/blocs/file_download/file_download_cubit.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/crypto/file_keys.dart';
import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

class _MockDownloader extends Mock implements ArDriveDownloader {}

/// The single-file download asks [FileKeys] for a private file's key, and
/// reads the cipher and IV from the data transaction's tags. Download
/// decrypts apart from preview (see docs and the preview tests), so it has
/// its own.
void main() {
  late MockDriveDao driveDao;
  late MockArweaveService arweave;
  late MockARFSRepository arfs;
  late _MockDownloader downloader;

  final cipherKey = SecretKey(List.filled(32, 1));
  final driveKey = DriveKey(SecretKey(List.filled(32, 2)), true);
  final fileKey = SecretKey(List.filled(32, 3));
  final file = createMockFile(driveId: 'drive', id: 'file', txId: 'data');

  TransactionCommonMixin$Tag tag(String name, String value) =>
      TransactionCommonMixin$Tag()
        ..name = name
        ..value = value;

  setUpAll(() => registerFallbackValue(SecretKey(const [0])));

  setUp(() {
    driveDao = MockDriveDao();
    arweave = MockArweaveService();
    arfs = MockARFSRepository();
    downloader = _MockDownloader();

    when(() => arfs.getDriveById('drive')).thenAnswer((_) async =>
        createMockDrive(driveId: 'drive', drivePrivacy: DrivePrivacy.private));
    final dataTx = MockTransactionCommonMixin();
    when(() => dataTx.tags).thenReturn([
      tag(EntityTag.cipher, 'AES256-GCM'),
      tag(EntityTag.cipherIv, 'the-iv'),
      tag(EntityTag.appName, 'ArDrive-Web'),
    ]);
    when(() => arweave.getTransactionDetails('data'))
        .thenAnswer((_) async => dataTx);
    when(() => driveDao.getFileKey('file', driveKey.key))
        .thenAnswer((_) async => fileKey);
    when(() => downloader.resumeEvents).thenAnswer((_) => const Stream.empty());
    when(() => downloader.integrity)
        .thenAnswer((_) async => const DataItemIntegrityResult.verified());
    when(() => downloader.downloadFile(
          txId: any(named: 'txId'),
          fileSize: any(named: 'fileSize'),
          fileName: any(named: 'fileName'),
          lastModifiedDate: any(named: 'lastModifiedDate'),
          contentType: any(named: 'contentType'),
          isManifest: any(named: 'isManifest'),
          cancelWithReason: any(named: 'cancelWithReason'),
          fileKey: any(named: 'fileKey'),
          cipher: any(named: 'cipher'),
          cipherIvString: any(named: 'cipherIvString'),
          verifyDownload: any(named: 'verifyDownload'),
          verifyIntegrity: any(named: 'verifyIntegrity'),
        )).thenAnswer((_) async => const Stream.empty());
  });

  ProfileFileDownloadCubit cubit() => ProfileFileDownloadCubit(
        file: file,
        arweave: arweave,
        downloader: MockArDriveDownloader(),
        arDriveDownloader: downloader,
        arfsRepository: arfs,
        crypto: MockArDriveCrypto(),
        fileKeys: FileKeys(driveDao: driveDao),
      );

  /// What the download was started with.
  ({SecretKey? key, String? cipher, String? iv}) started() {
    final call = verify(() => downloader.downloadFile(
          txId: 'data',
          fileSize: any(named: 'fileSize'),
          fileName: any(named: 'fileName'),
          lastModifiedDate: any(named: 'lastModifiedDate'),
          contentType: any(named: 'contentType'),
          isManifest: any(named: 'isManifest'),
          cancelWithReason: any(named: 'cancelWithReason'),
          fileKey: captureAny(named: 'fileKey'),
          cipher: captureAny(named: 'cipher'),
          cipherIvString: captureAny(named: 'cipherIvString'),
          verifyDownload: any(named: 'verifyDownload'),
          verifyIntegrity: any(named: 'verifyIntegrity'),
        ))
      ..called(1);
    final c = call.captured;
    return (
      key: c[0] as SecretKey?,
      cipher: c[1] as String?,
      iv: c[2] as String?
    );
  }

  test('a signed-in owner downloads with the key of their stored drive key',
      () async {
    when(() => driveDao.getDriveKey('drive', cipherKey))
        .thenAnswer((_) async => driveKey);

    await cubit().download(cipherKey);

    final s = started();
    expect(s.key, same(fileKey));
    expect(s.cipher, 'AES256-GCM');
    expect(s.iv, 'the-iv');
    verifyNever(() => driveDao.getDriveKeyFromMemory(any()));
  });

  test('a visitor downloads with the drive key held in memory', () async {
    when(() => driveDao.getDriveKeyFromMemory('drive'))
        .thenAnswer((_) async => driveKey);

    await cubit().download(null);

    expect(started().key, same(fileKey));
    verifyNever(() => driveDao.getDriveKey(any(), any()));
  });

  test('with no drive key the download fails and never starts', () async {
    when(() => driveDao.getDriveKeyFromMemory('drive'))
        .thenAnswer((_) async => null);
    final c = cubit();

    await c.download(null);

    expect(c.state, isA<FileDownloadFailure>());
    verifyNever(() => downloader.downloadFile(
          txId: any(named: 'txId'),
          fileSize: any(named: 'fileSize'),
          fileName: any(named: 'fileName'),
          lastModifiedDate: any(named: 'lastModifiedDate'),
          contentType: any(named: 'contentType'),
          isManifest: any(named: 'isManifest'),
        ));
  });
}
