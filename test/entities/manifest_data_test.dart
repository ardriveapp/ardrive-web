import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/manifest_data.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:test/test.dart';

import '../test_utils/utils.dart';
import 'expected_manifest_data.dart';

void main() {
  const stubEntityId = '00000000-0000-0000-0000-000000000000';
  const stubTxId = '0000000000000000000000000000000000000000001';
  final stubCurrentDate = DateTime.now();

  late final FileRepository fileRepository;
  late final FolderRepository folderRepository;

  final stubRootFolderEntry = FolderEntry(
    id: 'stubRootFolderEntry',
    dateCreated: stubCurrentDate,
    driveId: stubEntityId,
    isGhost: false,
    parentFolderId: stubEntityId,
    name: 'root-folder',
    lastUpdated: stubCurrentDate,
    isHidden: false,
    path: '',
  );

  final stubParentFolderEntry = FolderEntry(
    id: 'stubParentFolderEntry',
    dateCreated: stubCurrentDate,
    driveId: stubEntityId,
    isGhost: false,
    parentFolderId: stubEntityId,
    name: 'parent-folder',
    lastUpdated: stubCurrentDate,
    isHidden: false,
    path: '',
  );

  final stubChildFolderEntry = FolderEntry(
    id: 'stubChildFolderEntry',
    dateCreated: stubCurrentDate,
    driveId: stubEntityId,
    isGhost: false,
    parentFolderId: stubEntityId,
    name: 'child-folder',
    lastUpdated: stubCurrentDate,
    isHidden: false,
    path: '',
  );

  final stubFileInRoot1 = FileEntry(
    dataTxId: stubTxId,
    dateCreated: stubCurrentDate,
    size: 10,
    name: 'file-in-root-1',
    parentFolderId: stubEntityId,
    lastUpdated: stubCurrentDate,
    lastModifiedDate: stubCurrentDate,
    id: 'file-in-root-1-entity-id',
    driveId: stubEntityId,
    isHidden: false,
    path: '',
  );

  final stubFileInRoot2 = FileEntry(
    dataTxId: stubTxId,
    dateCreated: stubCurrentDate,
    size: 10,
    name: 'file-in-root-2',
    parentFolderId: stubEntityId,
    lastUpdated: stubCurrentDate,
    lastModifiedDate: stubCurrentDate,
    id: 'file-in-root-2-entity-id',
    driveId: stubEntityId,
    isHidden: false,
    path: '',
  );

  final stubFileInParent1 = FileEntry(
    dataTxId: stubTxId,
    dateCreated: stubCurrentDate,
    size: 10,
    name: 'file-in-parent-1',
    parentFolderId: stubEntityId,
    lastUpdated: stubCurrentDate,
    lastModifiedDate: stubCurrentDate,
    id: 'file-in-parent-1-entity-id',
    driveId: stubEntityId,
    isHidden: false,
    path: '',
  );

  final stubFileInParent2 = FileEntry(
    dataTxId: stubTxId,
    dateCreated: stubCurrentDate,
    size: 10,
    name: 'file-in-parent-2',
    parentFolderId: stubEntityId,
    lastUpdated: stubCurrentDate,
    lastModifiedDate: stubCurrentDate,
    id: 'file-in-parent-2-entity-id',
    driveId: stubEntityId,
    isHidden: false,
    path: '',
  );

  final stubFileInChild1 = FileEntry(
    dataTxId: stubTxId,
    dateCreated: stubCurrentDate,
    size: 10,
    name: 'file-in-child-1',
    parentFolderId: stubEntityId,
    lastUpdated: stubCurrentDate,
    lastModifiedDate: stubCurrentDate,
    id: 'file-in-child-1-entity-id',
    driveId: stubEntityId,
    isHidden: false,
    path: '',
  );

  final stubFileInChild2 = FileEntry(
    dataTxId: stubTxId,
    dateCreated: stubCurrentDate,
    size: 10,
    name: 'file-in-child-2',
    parentFolderId: stubEntityId,
    lastUpdated: stubCurrentDate,
    lastModifiedDate: stubCurrentDate,
    id: 'file-in-child-2-entity-id',
    driveId: stubEntityId,
    isHidden: false,
    path: '',
  );

  final stubManifestFileInChild = FileEntry(
    dataTxId: stubTxId,
    dateCreated: stubCurrentDate,
    size: 10,
    name: 'manifest-file-in-child',
    parentFolderId: stubEntityId,
    lastUpdated: stubCurrentDate,
    lastModifiedDate: stubCurrentDate,
    id: 'manifest-file-in-child-entity-id',
    driveId: stubEntityId,
    dataContentType: ContentType.manifest,
    isHidden: false,
    path: '',
  );

  final stubChildFolderNode =
      FolderNode(folder: stubChildFolderEntry, subfolders: [], files: {
    stubFileInChild1.id: stubFileInChild1,
    stubFileInChild2.id: stubFileInChild2,
    stubManifestFileInChild.id: stubManifestFileInChild
  });

  final stubParentFolderNode =
      FolderNode(folder: stubParentFolderEntry, subfolders: [
    stubChildFolderNode
  ], files: {
    stubFileInParent1.id: stubFileInParent1,
    stubFileInParent2.id: stubFileInParent2,
  });

  final stubRootFolderNode =
      FolderNode(folder: stubRootFolderEntry, subfolders: [
    stubParentFolderNode
  ], files: {
    stubFileInRoot1.id: stubFileInRoot1,
    stubFileInRoot2.id: stubFileInRoot2,
  });

  setUpAll(() {
    fileRepository = MockFileRepository();
    folderRepository = MockFolderRepository();

    when(() => folderRepository.getFolderPath(
            stubRootFolderNode.folder.driveId, stubRootFolderNode.folder.id))
        .thenAnswer((_) async => 'root-folder');
    when(() => folderRepository.getFolderPath(
            stubParentFolderEntry.driveId, stubParentFolderEntry.id))
        .thenAnswer((_) async => 'root-folder/parent-folder');
    when(() => folderRepository.getFolderPath(
            stubChildFolderEntry.driveId, stubChildFolderEntry.id))
        .thenAnswer((_) async => 'root-folder/parent-folder/child-folder');

    when(() => fileRepository.getFilePath(
            stubFileInRoot1.driveId, stubFileInRoot1.id))
        .thenAnswer((_) async => 'root-folder/file-in-root-1');
    when(() => fileRepository.getFilePath(
            stubFileInRoot2.driveId, stubFileInRoot2.id))
        .thenAnswer((_) async => 'root-folder/file-in-root-2');
    when(() => fileRepository.getFilePath(
            stubFileInParent1.driveId, stubFileInParent1.id))
        .thenAnswer((_) async => 'root-folder/parent-folder/file-in-parent-1');
    when(() => fileRepository.getFilePath(
            stubFileInParent2.driveId, stubFileInParent2.id))
        .thenAnswer((_) async => 'root-folder/parent-folder/file-in-parent-2');
    when(() =>
        fileRepository.getFilePath(
            stubFileInChild1.driveId, stubFileInChild1.id)).thenAnswer(
        (_) async => 'root-folder/parent-folder/child-folder/file-in-child-1');
    when(() =>
        fileRepository.getFilePath(
            stubFileInChild2.driveId, stubFileInChild2.id)).thenAnswer(
        (_) async => 'root-folder/parent-folder/child-folder/file-in-child-2');
  });
  group('ManifestDataBuilder Tests', () {
    test('returns a ManifestEntity with a valid expected manifest shape',
        () async {
      final builder = ManifestDataBuilder(
        folderRepository: folderRepository,
        fileRepository: fileRepository,
      );

      final manifest = await builder.build(folderNode: stubRootFolderNode);

      expect(
          manifest.toJson(),
          equals({
            'manifest': 'arweave/paths',
            'version': '0.2.0',
            'index': {'path': 'file-in-root-1'},
            'paths': {
              'file-in-root-1': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'file-in-root-2': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'parent-folder/file-in-parent-1': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'parent-folder/file-in-parent-2': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'parent-folder/child-folder/file-in-child-1': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'parent-folder/child-folder/file-in-child-2': {
                'id': '0000000000000000000000000000000000000000001'
              }
            }
          }));
    });

    test(
        'returns a ManifestEntity with a valid expected manifest shape when a fallback is provided',
        () async {
      final builder = ManifestDataBuilder(
        folderRepository: folderRepository,
        fileRepository: fileRepository,
      );

      final manifest = await builder.build(
        folderNode: stubRootFolderNode,
        fallbackTxId: 'fallback-tx-id',
      );

      expect(
          manifest.toJson(),
          equals({
            'manifest': 'arweave/paths',
            'version': '0.2.0',
            'index': {'path': 'file-in-root-1'},
            'fallback': {'id': 'fallback-tx-id'},
            'paths': {
              'file-in-root-1': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'file-in-root-2': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'parent-folder/file-in-parent-1': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'parent-folder/file-in-parent-2': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'parent-folder/child-folder/file-in-child-1': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'parent-folder/child-folder/file-in-child-2': {
                'id': '0000000000000000000000000000000000000000001'
              }
            }
          }));
    });

    test(
        'returns a ManifestEntity with a valid expected manifest shape with a nested child folder',
        () async {
      final builder = ManifestDataBuilder(
        folderRepository: folderRepository,
        fileRepository: fileRepository,
      );

      final manifest = await builder.build(
        folderNode: stubChildFolderNode,
      );

      expect(
          manifest.toJson(),
          equals({
            'manifest': 'arweave/paths',
            'version': '0.2.0',
            'index': {'path': 'file-in-child-1'},
            'paths': {
              'file-in-child-1': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'file-in-child-2': {
                'id': '0000000000000000000000000000000000000000001'
              }
            }
          }));
    });

    group('asPreparedDataItem method', () {
      PackageInfo.setMockInitialValues(
        version: '1.3.3.7',
        packageName: 'ArDrive-Web-Test',
        appName: 'ArDrive-Web-Test',
        buildNumber: '420',
        buildSignature: 'Test signature',
      );

      test('returns a DataItem with the expected tags, owner, and data',
          () async {
        final builder = ManifestDataBuilder(
          folderRepository: folderRepository,
          fileRepository: fileRepository,
        );

        final manifest = await builder.build(
          folderNode: stubRootFolderNode,
        );

        final wallet = getTestWallet();

        AppPlatform.setMockPlatform(platform: SystemPlatform.Android);

        final dataItem = await manifest.asPreparedDataItem(
          owner: await wallet.getOwner(),
        );

        logger.d(dataItem.data.toString());

        expect(dataItem.tags.length, equals(5));
        expect(decodeBase64ToString(dataItem.tags[0].name), equals('App-Name'));
        expect(decodeBase64ToString(dataItem.tags[0].value),
            equals('ArDrive-App'));
        expect(decodeBase64ToString(dataItem.tags[1].name),
            equals('App-Platform'));
        expect(decodeBase64ToString(dataItem.tags[1].value), equals('Android'));
        expect(
            decodeBase64ToString(dataItem.tags[2].name), equals('App-Version'));
        expect(decodeBase64ToString(dataItem.tags[2].value), equals('1.3.3.7'));
        expect(
            decodeBase64ToString(dataItem.tags[3].name), equals('Unix-Time'));
        expect(decodeBase64ToString(dataItem.tags[3].value).length, equals(10));
        expect(decodeBase64ToString(dataItem.tags[4].name),
            equals('Content-Type'));
        expect(decodeBase64ToString(dataItem.tags[4].value),
            equals('application/x.arweave-manifest+json'));

        expect(dataItem.target, equals(''));
        expect(dataItem.owner, equals(await wallet.getOwner()));

        expect(dataItem.data, equals(expectedManifestDataVersion020));
      });
      test(
          'returns a DataItem with the expected tags, owner, and data with fallback',
          () async {
        final builder = ManifestDataBuilder(
          folderRepository: folderRepository,
          fileRepository: fileRepository,
        );

        final manifest = await builder.build(
          folderNode: stubRootFolderNode,
          fallbackTxId: 'fallback-tx-id',
        );

        final wallet = getTestWallet();

        AppPlatform.setMockPlatform(platform: SystemPlatform.Android);

        final dataItem = await manifest.asPreparedDataItem(
          owner: await wallet.getOwner(),
        );

        expect(dataItem.tags.length, equals(5));
        expect(decodeBase64ToString(dataItem.tags[0].name), equals('App-Name'));
        expect(decodeBase64ToString(dataItem.tags[0].value),
            equals('ArDrive-App'));
        expect(decodeBase64ToString(dataItem.tags[1].name),
            equals('App-Platform'));
        expect(decodeBase64ToString(dataItem.tags[1].value), equals('Android'));
        expect(
            decodeBase64ToString(dataItem.tags[2].name), equals('App-Version'));
        expect(decodeBase64ToString(dataItem.tags[2].value), equals('1.3.3.7'));
        expect(
            decodeBase64ToString(dataItem.tags[3].name), equals('Unix-Time'));
        expect(decodeBase64ToString(dataItem.tags[3].value).length, equals(10));
        expect(decodeBase64ToString(dataItem.tags[4].name),
            equals('Content-Type'));
        expect(decodeBase64ToString(dataItem.tags[4].value),
            equals('application/x.arweave-manifest+json'));

        expect(dataItem.target, equals(''));
        expect(dataItem.owner, equals(await wallet.getOwner()));

        expect(dataItem.data, equals(expectedManifestDataWithFallback));
      });
    });
  });
}
