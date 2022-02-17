import 'package:ardrive/entities/manifest_entity.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:test/test.dart';

void main() {
  final stubEntityId = '00000000-0000-0000-0000-000000000000';
  final stubTxId = '0000000000000000000000000000000000000000001';
  final stubCurrentDate = DateTime.now();

  final stubRootFolderEntry = FolderEntry(
      id: stubEntityId,
      dateCreated: stubCurrentDate,
      driveId: stubEntityId,
      isGhost: false,
      parentFolderId: stubEntityId,
      path: '/root-folder',
      name: 'root-folder',
      lastUpdated: stubCurrentDate);

  final stubParentFolderEntry = FolderEntry(
      id: stubEntityId,
      dateCreated: stubCurrentDate,
      driveId: stubEntityId,
      isGhost: false,
      parentFolderId: stubEntityId,
      path: '/root-folder/parent-folder',
      name: 'parent-folder',
      lastUpdated: stubCurrentDate);

  final stubChildFolderEntry = FolderEntry(
      id: stubEntityId,
      dateCreated: stubCurrentDate,
      driveId: stubEntityId,
      isGhost: false,
      parentFolderId: stubEntityId,
      path: '/root-folder/parent-folder/child-folder',
      name: 'child-folder',
      lastUpdated: stubCurrentDate);

  final stubFileInRoot1 = FileEntry(
      dataTxId: stubTxId,
      dateCreated: stubCurrentDate,
      size: 10,
      path: '/root-folder/file-in-root-1',
      name: 'file-in-root-1',
      parentFolderId: stubEntityId,
      lastUpdated: stubCurrentDate,
      lastModifiedDate: stubCurrentDate,
      id: 'file-in-root-1-entity-id',
      driveId: stubEntityId);

  final stubFileInRoot2 = FileEntry(
      dataTxId: stubTxId,
      dateCreated: stubCurrentDate,
      size: 10,
      path: '/root-folder/file-in-root-2',
      name: 'file-in-root-2',
      parentFolderId: stubEntityId,
      lastUpdated: stubCurrentDate,
      lastModifiedDate: stubCurrentDate,
      id: 'file-in-root-2-entity-id',
      driveId: stubEntityId);

  final stubFileInParent1 = FileEntry(
      dataTxId: stubTxId,
      dateCreated: stubCurrentDate,
      size: 10,
      path: '/root-folder/parent-folder/file-in-parent-1',
      name: 'file-in-parent-1',
      parentFolderId: stubEntityId,
      lastUpdated: stubCurrentDate,
      lastModifiedDate: stubCurrentDate,
      id: 'file-in-parent-1-entity-id',
      driveId: stubEntityId);

  final stubFileInParent2 = FileEntry(
      dataTxId: stubTxId,
      dateCreated: stubCurrentDate,
      size: 10,
      path: '/root-folder/parent-folder/file-in-parent-2',
      name: 'file-in-parent-2',
      parentFolderId: stubEntityId,
      lastUpdated: stubCurrentDate,
      lastModifiedDate: stubCurrentDate,
      id: 'file-in-parent-2-entity-id',
      driveId: stubEntityId);

  final stubFileInChild1 = FileEntry(
      dataTxId: stubTxId,
      dateCreated: stubCurrentDate,
      size: 10,
      path: '/root-folder/parent-folder/child-folder/file-in-child-1',
      name: 'file-in-child-1',
      parentFolderId: stubEntityId,
      lastUpdated: stubCurrentDate,
      lastModifiedDate: stubCurrentDate,
      id: 'file-in-child-1-entity-id',
      driveId: stubEntityId);

  final stubFileInChild2 = FileEntry(
      dataTxId: stubTxId,
      dateCreated: stubCurrentDate,
      size: 10,
      path: '/root-folder/parent-folder/child-folder/file-in-child-2',
      name: 'file-in-child-2',
      parentFolderId: stubEntityId,
      lastUpdated: stubCurrentDate,
      lastModifiedDate: stubCurrentDate,
      id: 'file-in-child-2-entity-id',
      driveId: stubEntityId);

  final stubChildFolderNode =
      FolderNode(folder: stubChildFolderEntry, subfolders: [], files: {
    stubFileInChild1.id: stubFileInChild1,
    stubFileInChild2.id: stubFileInChild2,
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

  group('ManifestEntity Tests', () {
    group('fromFolderNode static method', () {
      test('returns a ManifestEntity with a valid expected manifest shape',
          () async {
        final manifest =
            ManifestEntity.fromFolderNode(folderNode: stubRootFolderNode);

        expect(
            manifest.toJson(),
            equals({
              'manifest': 'arweave/paths',
              'version': '0.1.0',
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
          'returns a ManifestEntity with a valid expected manifest shape with a nested child folder',
          () async {
        final manifest =
            ManifestEntity.fromFolderNode(folderNode: stubChildFolderNode);

        expect(
            manifest.toJson(),
            equals({
              'manifest': 'arweave/paths',
              'version': '0.1.0',
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
    });
  });
}
