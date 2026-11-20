import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/crypto/file_keys.dart';
import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

class _MockDownloader extends Mock implements ArDriveDownloader {}

class _MockDrive extends Mock implements Drive {}

class _MockUser extends Mock implements User {}

class _MockSelectable<T> extends Mock implements Selectable<T> {}

/// A private file's thumbnail is encrypted with the file's key, which the
/// repository asks FileKeys for: the signed-in profile's stored drive key,
/// or for a visitor the one in memory.
void main() {
  late MockDriveDao driveDao;
  late MockArDriveAuth auth;
  late _MockDownloader downloader;
  late ThumbnailRepository repository;

  final driveKey = DriveKey(SecretKey(List.filled(32, 2)), true);
  final fileKey = SecretKey(List.filled(32, 3));

  final item = FileDataTableItem(
    fileId: 'file',
    driveId: 'drive',
    parentFolderId: 'folder',
    dataTxId: 'data',
    lastUpdated: DateTime(2026),
    lastModifiedDate: DateTime(2026),
    name: 'photo.jpg',
    size: 10,
    dateCreated: DateTime(2026),
    contentType: 'image/jpeg',
    index: 0,
    isOwner: true,
    dataTx: null,
    metadataTx: null,
    pinnedDataOwnerAddress: null,
    thumbnail: Thumbnail(variants: [
      Variant(name: 'small', txId: 'thumb', size: 5, width: 1, height: 1),
    ]),
  );

  setUpAll(() => registerFallbackValue(SecretKey(const [0])));

  setUp(() {
    driveDao = MockDriveDao();
    auth = MockArDriveAuth();
    downloader = _MockDownloader();
    final arweave = MockArweaveService();

    final drive = _MockDrive();
    when(() => drive.isPrivate).thenReturn(true);
    when(() => drive.privacy).thenReturn(DrivePrivacyTag.private);
    final selectable = _MockSelectable<Drive>();
    when(() => selectable.getSingle()).thenAnswer((_) async => drive);
    when(() => driveDao.driveById(driveId: 'drive')).thenReturn(selectable);

    // The thumbnail's cipher tags come from the batched tag query.
    when(() => arweave.getTagsForTransactions(['thumb'])).thenAnswer(
      (_) async => {
        'thumb': {EntityTag.cipher: 'AES256-GCM', EntityTag.cipherIv: 'the-iv'},
      },
    );
    when(() => driveDao.getFileKey('file', driveKey.key))
        .thenAnswer((_) async => fileKey);
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
        )).thenAnswer((_) async => Uint8List.fromList([1, 2]));

    repository = ThumbnailRepository(
      arweaveService: arweave,
      arDriveDownloader: downloader,
      driveDao: driveDao,
      fileKeys: FileKeys(driveDao: driveDao),
      arDriveAuth: auth,
      arDriveUploader: MockArDriveUploader(),
      turboUploadService: MockTurboUploadService(),
    );
  });

  SecretKey? keyUsed() => verify(() => downloader.downloadToMemory(
        txId: 'thumb',
        fileSize: any(named: 'fileSize'),
        fileName: any(named: 'fileName'),
        lastModifiedDate: any(named: 'lastModifiedDate'),
        contentType: any(named: 'contentType'),
        isManifest: any(named: 'isManifest'),
        fileKey: captureAny(named: 'fileKey'),
        cipher: 'AES256-GCM',
        cipherIvString: 'the-iv',
      )).captured.single as SecretKey?;

  test('a signed-in owner decrypts with their stored drive key', () async {
    final user = _MockUser();
    final cipherKey = SecretKey(List.filled(32, 1));
    when(() => user.cipherKey).thenReturn(cipherKey);
    when(() => auth.currentUser).thenReturn(user);
    when(() => driveDao.getDriveKey('drive', cipherKey))
        .thenAnswer((_) async => driveKey);

    final data = await repository.getThumbnail(fileDataTableItem: item);

    expect(data.data, [1, 2]);
    expect(keyUsed(), same(fileKey));
    verifyNever(() => driveDao.getDriveKeyFromMemory(any()));
  });

  test('a visitor decrypts with the drive key held in memory', () async {
    when(() => auth.currentUser)
        .thenThrow(const AuthenticationUserIsNotLoggedInException());
    when(() => driveDao.getDriveKeyFromMemory('drive'))
        .thenAnswer((_) async => driveKey);

    await repository.getThumbnail(fileDataTableItem: item);

    expect(keyUsed(), same(fileKey));
    verifyNever(() => driveDao.getDriveKey(any(), any()));
  });
}
