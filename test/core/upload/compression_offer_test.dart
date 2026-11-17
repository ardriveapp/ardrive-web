import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/blocs/upload/models/web_folder.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/upload/compression_offer.dart';
import 'package:ardrive/core/upload/domain/repository/upload_repository.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';
import '../../utils/io_utils_test.dart';

class MockArDriveUploader extends Mock implements ArDriveUploader {}

class MockDriveDao extends Mock implements DriveDao {}

class MockArDriveAuth extends Mock implements ArDriveAuth {}

class MockLicenseService extends Mock implements LicenseService {}

class MockDrive extends Mock implements Drive {}

class MockFolderEntry extends Mock implements FolderEntry {}

class MockUploadController extends Mock implements UploadController {}

/// A file at [path], as the picker reports it.
class _PathedFile extends IOFile {
  _PathedFile(this.path, {super.contentType = 'text/plain'});

  @override
  final String path;

  @override
  String get name => path.split('/').last;

  @override
  DateTime get lastModifiedDate => DateTime(2026, 11, 16);

  @override
  FutureOr<int> get length => 1;

  @override
  Stream<Uint8List> openReadStream([int start = 0, int? end]) async* {
    yield Uint8List(1);
  }

  @override
  Future<Uint8List> readAsBytes() async => Uint8List(1);

  @override
  Future<String> readAsString() async => '';
}

UploadFile _file(String path, {String contentType = 'text/plain'}) =>
    UploadFile(
      ioFile: _PathedFile(path, contentType: contentType),
      parentFolderId: 'folder-id',
    );

void main() {
  group('offersCompression', () {
    bool offered(
      List<UploadFile> files, {
      bool switchOn = true,
      bool isPublic = true,
      int length = 1000,
    }) =>
        offersCompression(
          switchOn: switchOn,
          isPublic: isPublic,
          files: files,
          lengths: {for (final f in files) f.getIdentifier(): length},
        );

    test('is offered for a public drive with a file the policy compresses', () {
      expect(
          offered([_file('app.js', contentType: 'text/javascript')]), isTrue);
    });

    test('a loose file or a nested folder needs no index.html', () {
      expect(offered([_file('notes.txt')]), isTrue);
      expect(
          offered([_file('a/b/c/style.css', contentType: 'text/css')]), isTrue);
    });

    test('is not offered with the config switch off', () {
      expect(offered([_file('app.js')], switchOn: false), isFalse);
    });

    test('is not offered on a private drive', () {
      expect(offered([_file('app.js')], isPublic: false), isFalse);
    });

    test('is not offered when nothing in the upload is compressible', () {
      expect(
        offered([
          _file('photo.png', contentType: 'image/png'),
          _file('song.mp3', contentType: 'audio/mpeg'),
          _file('doc.pdf', contentType: 'application/pdf'),
        ]),
        isFalse,
      );
    });

    test('one compressible file among others is enough', () {
      expect(
        offered([
          _file('photo.png', contentType: 'image/png'),
          _file('page.html', contentType: 'text/html'),
        ]),
        isTrue,
      );
    });

    test('a file over the 8 MiB cap does not count', () {
      expect(
        offered([_file('big.json')],
            length: CompressionPolicy.maxCompressibleBytes + 1),
        isFalse,
      );
    });

    test('an empty selection and unknown lengths offer nothing', () {
      expect(offered(const []), isFalse);
      expect(
        offersCompression(
          switchOn: true,
          isPublic: true,
          files: [_file('app.js')],
          lengths: const {},
        ),
        isFalse,
      );
    });
  });

  group('UploadRepository and compression', () {
    late UploadRepository repository;
    late MockArDriveUploader uploader;
    late MockDriveDao driveDao;
    late MockArDriveAuth auth;

    setUp(() {
      uploader = MockArDriveUploader();
      driveDao = MockDriveDao();
      auth = MockArDriveAuth();
      repository = UploadRepository(
        ardriveUploader: uploader,
        driveDao: driveDao,
        auth: auth,
        licenseService: MockLicenseService(),
        ardriveIO: MockArDriveIO(),
      );
      registerFallbackValue(getTestWallet());
      registerFallbackValue(UploadType.turbo);
      registerFallbackValue(SecretKey([1, 2, 3, 4, 5]));
      when(() => auth.currentUser).thenReturn(getTestUser());
      when(() => uploader.uploadEntities(
            entities: any(named: 'entities'),
            wallet: any(named: 'wallet'),
            uploadThumbnail: any(named: 'uploadThumbnail'),
            type: any(named: 'type'),
            driveKey: any(named: 'driveKey'),
          )).thenAnswer((_) async => MockUploadController());
      when(() => uploader.uploadFiles(
            files: any(named: 'files'),
            wallet: any(named: 'wallet'),
            uploadThumbnail: any(named: 'uploadThumbnail'),
            type: any(named: 'type'),
            driveKey: any(named: 'driveKey'),
          )).thenAnswer((_) async => MockUploadController());
      when(() => driveDao.getDriveKey(any(), any()))
          .thenAnswer((_) async => DriveKey(SecretKey([1, 2, 3, 4, 5]), true));
    });

    (MockDrive, MockFolderEntry) targets({required bool isPrivate}) {
      final drive = MockDrive();
      final folder = MockFolderEntry();
      when(() => drive.privacy).thenReturn(isPrivate ? 'private' : 'public');
      when(() => drive.id).thenReturn('drive-id');
      when(() => folder.id).thenReturn('folder-id');
      return (drive, folder);
    }

    /// What [UploadRepository.uploadFolders] handed the uploader per file.
    Future<List<bool>> folderFlags({
      required List<String> paths,
      required bool isPrivate,
      bool? compress,
    }) async {
      final (drive, folder) = targets(isPrivate: isPrivate);
      await repository.uploadFolders(
        files: [for (final p in paths) _file(p)],
        targetDrive: drive,
        conflictingFiles: {},
        conflictingFolders: [],
        targetFolder: folder,
        uploadMethod: UploadMethod.turbo,
        foldersByPath: <String, WebFolder>{},
        uploadThumbnail: false,
        compressTextAndCode: compress ?? false,
      );
      final entities = verify(() => uploader.uploadEntities(
            entities: captureAny(named: 'entities'),
            wallet: any(named: 'wallet'),
            uploadThumbnail: any(named: 'uploadThumbnail'),
            type: any(named: 'type'),
            driveKey: any(named: 'driveKey'),
          )).captured.single as List<(ARFSUploadMetadataArgs, IOEntity)>;
      return [for (final e in entities) e.$1.compressDeployment];
    }

    /// The same for [UploadRepository.uploadFiles], loose files.
    Future<List<bool>> fileFlags({
      required List<String> paths,
      required bool isPrivate,
      bool? compress,
    }) async {
      final (drive, folder) = targets(isPrivate: isPrivate);
      await repository.uploadFiles(
        files: [for (final p in paths) _file(p)],
        targetDrive: drive,
        conflictingFiles: {},
        targetFolder: folder,
        uploadMethod: UploadMethod.turbo,
        uploadThumbnail: false,
        compressTextAndCode: compress ?? false,
      );
      final files = verify(() => uploader.uploadFiles(
            files: captureAny(named: 'files'),
            wallet: any(named: 'wallet'),
            uploadThumbnail: any(named: 'uploadThumbnail'),
            type: any(named: 'type'),
            driveKey: any(named: 'driveKey'),
          )).captured.single as List<(ARFSUploadMetadataArgs, IOFile)>;
      return [for (final f in files) f.$1.compressDeployment];
    }

    const tree = ['site/app.js', 'site/css/a.css', 'notes/readme.txt'];
    const loose = ['a.js', 'b.css'];

    test('a folder with no index.html is compressed when chosen', () async {
      expect(
        await folderFlags(paths: tree, isPrivate: false, compress: true),
        [true, true, true],
      );
    });

    test('a folder with an index.html is not special', () async {
      expect(
        await folderFlags(
            paths: ['site/index.html', 'notes/a.js'],
            isPrivate: false,
            compress: true),
        [true, true],
      );
      expect(
        await folderFlags(
            paths: ['site/index.html', 'notes/a.js'], isPrivate: false),
        [false, false],
      );
    });

    test('loose files are compressed when chosen', () async {
      expect(
        await fileFlags(paths: loose, isPrivate: false, compress: true),
        [true, true],
      );
    });

    test('folders: nothing is compressed unless chosen', () async {
      expect(await folderFlags(paths: tree, isPrivate: false),
          [false, false, false]);
      expect(await folderFlags(paths: tree, isPrivate: false, compress: false),
          [false, false, false]);
    });

    test('loose files: nothing is compressed unless chosen', () async {
      expect(await fileFlags(paths: loose, isPrivate: false), [false, false]);
      expect(await fileFlags(paths: loose, isPrivate: false, compress: false),
          [false, false]);
    });

    test('a private drive is never compressed, folders or loose files',
        () async {
      expect(await folderFlags(paths: tree, isPrivate: true, compress: true),
          [false, false, false]);
      expect(await fileFlags(paths: loose, isPrivate: true, compress: true),
          [false, false]);
    });
  });
}
