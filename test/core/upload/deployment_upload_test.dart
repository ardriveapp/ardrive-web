import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/blocs/upload/models/web_folder.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/upload/deployment_upload.dart';
import 'package:ardrive/core/upload/domain/repository/upload_repository.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
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

/// A file at [path], as the folder picker reports it.
class _PathedFile extends IOFile {
  _PathedFile(this.path) : super(contentType: 'text/plain');

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

UploadFile _file(String path, {String? relativeTo}) => UploadFile(
      ioFile: _PathedFile(path),
      parentFolderId: 'folder-id',
      relativeTo: relativeTo,
    );

void main() {
  group('deploymentRoots', () {
    Set<String> roots(List<String> paths) =>
        deploymentRoots([for (final p in paths) _file(p)]);

    test('a folder with an index.html directly inside it is a site', () {
      expect(roots(['site/index.html', 'site/app.js']), {'site'});
    });

    test('a bare index.html is a flat selection, not a site', () {
      expect(roots(['index.html', 'app.js']), isEmpty);
    });

    test('a mobile path is read relative to the picked folder', () {
      final files = [
        _file('/storage/emulated/0/site/index.html',
            relativeTo: '/storage/emulated/0'),
        _file('/storage/emulated/0/site/app.js',
            relativeTo: '/storage/emulated/0'),
      ];
      expect(deploymentRoots(files), {'site'});
      expect(isInDeployment(files.last, {'site'}), isTrue);
    });

    test('an index.html only in a subfolder is not the site root', () {
      expect(roots(['photos/2026/index.html', 'photos/2026/a.js']), isEmpty);
    });

    test('two folders: only the one with a root index.html is a site', () {
      final files = [
        _file('site/index.html'),
        _file('site/app.js'),
        _file('notes/a.js'),
        _file('notes/sub/index.html'),
      ];
      final found = deploymentRoots(files);
      expect(found, {'site'});
      expect([for (final f in files) isInDeployment(f, found)],
          [true, true, false, false]);
    });

    test('only the exact name counts', () {
      expect(roots(['site/Index.html']), isEmpty);
      expect(roots(['site/index.htm']), isEmpty);
      expect(roots(['site/myindex.html']), isEmpty);
      expect(roots(const []), isEmpty);
    });
  });

  group('UploadRepository.uploadFolders and compression', () {
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
    });

    /// What [uploadFolders] handed the uploader for each file it was given.
    Future<List<bool>> compressFlags({
      required List<String> paths,
      required bool isPrivate,
      required bool compressDeployments,
    }) async {
      final drive = MockDrive();
      final folder = MockFolderEntry();
      when(() => drive.privacy).thenReturn(isPrivate ? 'private' : 'public');
      when(() => drive.id).thenReturn('drive-id');
      when(() => folder.id).thenReturn('folder-id');
      when(() => driveDao.getDriveKey(any(), any()))
          .thenAnswer((_) async => DriveKey(SecretKey([1, 2, 3, 4, 5]), true));

      final controller = await repository.uploadFolders(
        files: [for (final p in paths) _file(p)],
        targetDrive: drive,
        conflictingFiles: {},
        conflictingFolders: [],
        targetFolder: folder,
        uploadMethod: UploadMethod.turbo,
        foldersByPath: <String, WebFolder>{},
        uploadThumbnail: false,
        compressDeployments: compressDeployments,
      );
      expect(controller, isA<UploadController>());

      final entities = verify(() => uploader.uploadEntities(
            entities: captureAny(named: 'entities'),
            wallet: any(named: 'wallet'),
            uploadThumbnail: any(named: 'uploadThumbnail'),
            type: any(named: 'type'),
            driveKey: any(named: 'driveKey'),
          )).captured.single as List<(ARFSUploadMetadataArgs, IOEntity)>;
      return [for (final e in entities) e.$1.compressDeployment];
    }

    const site = ['site/index.html', 'site/app.js', 'site/css/a.css'];

    test('a site on a public drive, with the switch on, is compressed',
        () async {
      expect(
        await compressFlags(
            paths: site, isPrivate: false, compressDeployments: true),
        [true, true, true],
      );
    });

    test('with the switch off, nothing is compressed', () async {
      expect(
        await compressFlags(
            paths: site, isPrivate: false, compressDeployments: false),
        [false, false, false],
      );
    });

    test('a private drive is never compressed', () async {
      expect(
        await compressFlags(
            paths: site, isPrivate: true, compressDeployments: true),
        [false, false, false],
      );
    });

    test('two folders: only the files of the site folder are compressed',
        () async {
      expect(
        await compressFlags(
          paths: ['site/index.html', 'site/app.js', 'notes/a.js'],
          isPrivate: false,
          compressDeployments: true,
        ),
        [true, true, false],
      );
    });

    test('a flat selection with an index.html is never compressed', () async {
      expect(
        await compressFlags(
          paths: ['index.html', 'app.js'],
          isPrivate: false,
          compressDeployments: true,
        ),
        [false, false],
      );
    });

    test('a folder that is not a site is never compressed', () async {
      expect(
        await compressFlags(
          paths: ['notes/a.txt', 'notes/b.js'],
          isPrivate: false,
          compressDeployments: true,
        ),
        [false, false],
      );
    });

    test('the switch is off unless it is passed', () async {
      final drive = MockDrive();
      final folder = MockFolderEntry();
      when(() => drive.privacy).thenReturn('public');
      when(() => drive.id).thenReturn('drive-id');
      when(() => folder.id).thenReturn('folder-id');

      await repository.uploadFolders(
        files: [_file('site/index.html')],
        targetDrive: drive,
        conflictingFiles: {},
        conflictingFolders: [],
        targetFolder: folder,
        uploadMethod: UploadMethod.turbo,
        foldersByPath: <String, WebFolder>{},
        uploadThumbnail: false,
      );

      final entities = verify(() => uploader.uploadEntities(
            entities: captureAny(named: 'entities'),
            wallet: any(named: 'wallet'),
            uploadThumbnail: any(named: 'uploadThumbnail'),
            type: any(named: 'type'),
            driveKey: any(named: 'driveKey'),
          )).captured.single as List<(ARFSUploadMetadataArgs, IOEntity)>;
      expect(entities.single.$1.compressDeployment, isFalse);
    });
  });
}
