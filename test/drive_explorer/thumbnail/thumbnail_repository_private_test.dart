import 'dart:typed_data';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/arweave/transaction_tag_batcher.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Arweave extends Mock implements ArweaveService {}

class _Downloader extends Mock implements ArDriveDownloader {}

class _Dao extends Mock implements DriveDao {}

class _Auth extends Mock implements ArDriveAuth {}

class _Uploader extends Mock implements ArDriveUploader {}

class _Turbo extends Mock implements TurboUploadService {}

void main() {
  late _Arweave arweave;
  late _Downloader downloader;
  late _Dao dao;
  late _Auth auth;
  late List<String> batched;
  late ThumbnailRepository repo;
  var known = <String>{};

  setUpAll(() {
    registerFallbackValue(SecretKey([0]));
    registerFallbackValue(DateTime(2026));
  });

  setUp(() {
    arweave = _Arweave();
    downloader = _Downloader();
    dao = _Dao();
    auth = _Auth();
    batched = [];
    known = {'t1', 't2'};
    when(() => auth.currentUser)
        .thenThrow(const AuthenticationUserIsNotLoggedInException());
    when(() => dao.getDriveKeyFromMemory(any()))
        .thenAnswer((_) async => DriveKey(SecretKey([1, 2, 3]), false));
    when(() => dao.getFileKey(any(), any()))
        .thenAnswer((_) async => SecretKey([4, 5, 6]));
    when(() => downloader.downloadToMemory(
          txId: any(named: 'txId'),
          fileSize: any(named: 'fileSize'),
          fileName: any(named: 'fileName'),
          lastModifiedDate: any(named: 'lastModifiedDate'),
          contentType: any(named: 'contentType'),
          isManifest: any(named: 'isManifest'),
          fileKey: any(named: 'fileKey'),
          cipher: any(named: 'cipher'),
          cipherIvString: any(named: 'cipherIvString'),
        )).thenAnswer((_) async => Uint8List(1));

    repo = ThumbnailRepository(
      arweaveService: arweave,
      arDriveDownloader: downloader,
      driveDao: dao,
      arDriveAuth: auth,
      arDriveUploader: _Uploader(),
      turboUploadService: _Turbo(),
      tagBatcher: TransactionTagBatcher(
        fetch: (ids) async {
          batched.addAll(ids);
          return {
            for (final id in ids)
              if (known.contains(id))
                id: {'Cipher': 'AES256-GCM', 'Cipher-IV': 'iv-$id'},
          };
        },
      ),
    );
  });

  Future<Uint8List> fetch(String tx) => repo.fetchPrivateVariantBytes(
        fileId: 'f-$tx',
        driveId: 'd',
        txId: tx,
        size: 10,
        fileName: 'a.jpg',
        lastModifiedDate: DateTime(2026),
      );

  test('private thumbnail reads its cipher tags through the batcher', () async {
    await Future.wait([fetch('t1'), fetch('t2')]);

    expect(batched, ['t1', 't2']);
    verifyNever(() => arweave.getTransactionDetails(any()));
    verify(() => downloader.downloadToMemory(
          txId: 't1',
          fileSize: 10,
          fileName: 'a.jpg',
          lastModifiedDate: any(named: 'lastModifiedDate'),
          contentType: 'image/jpeg',
          isManifest: false,
          fileKey: any(named: 'fileKey'),
          cipher: 'AES256-GCM',
          cipherIvString: 'iv-t1',
        )).called(1);
  });

  test('a transaction the gateway has no node for is not found', () async {
    await expectLater(
      fetch('missing'),
      throwsA(isA<TransactionNotFoundException>()),
    );
    verifyNever(() => downloader.downloadToMemory(
          txId: any(named: 'txId'),
          fileSize: any(named: 'fileSize'),
          fileName: any(named: 'fileName'),
          lastModifiedDate: any(named: 'lastModifiedDate'),
          contentType: any(named: 'contentType'),
          isManifest: any(named: 'isManifest'),
          fileKey: any(named: 'fileKey'),
          cipher: any(named: 'cipher'),
          cipherIvString: any(named: 'cipherIvString'),
        ));
  });
}
