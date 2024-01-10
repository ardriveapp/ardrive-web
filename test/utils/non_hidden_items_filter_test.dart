import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/utils/non_hidden_items_filter.dart';
import 'package:flutter_test/flutter_test.dart';

final NetworkTransaction networkTransaction = NetworkTransaction(
  id: 'id',
  status: 'pending',
  dateCreated: DateTime(12345),
  transactionDateCreated: DateTime(12345),
);

void main() {
  group('Non hidden items filter', () {
    final List<ArDriveDataTableItem> dataTableItems = [
      // non hidden
      FolderDataTableItem(
        driveId: 'drive id',
        folderId: 'folder id',
        name: 'folder name',
        lastUpdated: DateTime(12345),
        dateCreated: DateTime(12345),
        contentType: 'application/json',
        path: '/path/to/folder',
        isHidden: false,
        index: 0,
        isOwner: true,
      ),
      FileDataTableItem(
        driveId: 'drive id',
        fileId: 'file id',
        name: 'file name',
        lastUpdated: DateTime(12345),
        dateCreated: DateTime(12345),
        lastModifiedDate: DateTime(12345),
        contentType: 'application/json',
        path: '/path/to/file',
        isHidden: false,
        index: 0,
        isOwner: true,
        size: 1234,
        parentFolderId: 'folder id',
        dataTxId: 'data tx id',
        metadataTx: null,
        dataTx: null,
        pinnedDataOwnerAddress: null,
        bundledIn: null,
      ),

      // hidden
      FolderDataTableItem(
        driveId: 'drive id',
        folderId: 'folder id',
        name: 'folder name',
        lastUpdated: DateTime(12345),
        dateCreated: DateTime(12345),
        contentType: 'application/json',
        path: '/path/to/folder',
        isHidden: true,
        index: 0,
        isOwner: true,
      ),
      FileDataTableItem(
        driveId: 'drive id',
        fileId: 'file id',
        name: 'file name',
        lastUpdated: DateTime(12345),
        dateCreated: DateTime(12345),
        lastModifiedDate: DateTime(12345),
        contentType: 'application/json',
        path: '/path/to/file',
        isHidden: true,
        index: 0,
        isOwner: true,
        size: 1234,
        parentFolderId: 'folder id',
        dataTxId: 'data tx id',
        metadataTx: null,
        dataTx: null,
        pinnedDataOwnerAddress: null,
        bundledIn: null,
      ),
    ];
    final List<FolderEntry> folderEntries = [
      // non hidden
      FolderEntry(
        id: 'folder id',
        driveId: 'drive id',
        name: 'folder name',
        parentFolderId: 'parent folder id',
        path: '/path/to/folder',
        dateCreated: DateTime(12345),
        lastUpdated: DateTime(12345),
        isGhost: false,
        customJsonMetadata: null,
        customGQLTags: null,
        isHidden: false,
      ),

      // hidden
      FolderEntry(
        id: 'folder id',
        driveId: 'drive id',
        name: 'folder name',
        parentFolderId: 'parent folder id',
        path: '/path/to/folder',
        dateCreated: DateTime(12345),
        lastUpdated: DateTime(12345),
        isGhost: false,
        customJsonMetadata: null,
        customGQLTags: null,
        isHidden: true,
      ),
    ];
    final List<FileWithLatestRevisionTransactions> fileEntries = [
      // non hidden
      FileWithLatestRevisionTransactions(
        id: 'file id',
        driveId: 'drive id',
        name: 'file name',
        parentFolderId: 'parent folder id',
        path: '/path/to/file',
        dateCreated: DateTime(12345),
        lastUpdated: DateTime(12345),
        lastModifiedDate: DateTime(12345),
        customJsonMetadata: null,
        customGQLTags: null,
        isHidden: false,
        size: 1234,
        dataTxId: 'data tx id',
        metadataTx: networkTransaction,
        dataTx: networkTransaction,
        pinnedDataOwnerAddress: null,
        bundledIn: null,
      ),

      // hidden
      FileWithLatestRevisionTransactions(
        id: 'file id',
        driveId: 'drive id',
        name: 'file name',
        parentFolderId: 'parent folder id',
        path: '/path/to/file',
        dateCreated: DateTime(12345),
        lastUpdated: DateTime(12345),
        lastModifiedDate: DateTime(12345),
        customJsonMetadata: null,
        customGQLTags: null,
        isHidden: true,
        size: 1234,
        dataTxId: 'data tx id',
        metadataTx: networkTransaction,
        dataTx: networkTransaction,
        pinnedDataOwnerAddress: null,
        bundledIn: null,
      ),
    ];

    test('dataTableNotHiddenFilter function filters out hidden items', () {
      final List<ArDriveDataTableItem> filteredItems =
          dataTableItems.where(dataTableNotHiddenFilter).toList();
      expect(filteredItems.length, 2);
      expect(filteredItems[0].isHidden, false);
      expect(filteredItems[1].isHidden, false);
    });

    test('folderEntryNotHiddenFilter function filters out hidden items', () {
      final List<FolderEntry> filteredItems =
          folderEntries.where(folderEntryNotHiddenFilter).toList();
      expect(filteredItems.length, 1);
      expect(filteredItems[0].isHidden, false);
    });

    test('fileEntryNotHiddenFilter function filters out hidden items', () {
      final List<FileWithLatestRevisionTransactions> filteredItems =
          fileEntries.where(fileEntryNotHiddenFilter).toList();
      expect(filteredItems.length, 1);
      expect(filteredItems[0].isHidden, false);
    });
  });
}
