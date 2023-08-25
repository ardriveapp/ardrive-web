import 'package:ardrive/download/download_utils.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/utils/data_size.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

void main() {
  final mockFolderB = FolderNode(
    folder: createMockFolderEntry(name: 'b'),
    subfolders: [],
    files: {
      'b0': createMockFileEntry(name: 'b0.txt', size: 75, dataTxId: 'b0')
    },
  );

  final mockFolderA = FolderNode(
    folder: createMockFolderEntry(name: 'a'),
    subfolders: [mockFolderB],
    files: {
      'a0': createMockFileEntry(name: 'a0.txt', size: 85, dataTxId: 'a0'),
    },
  );

  group('convertFolderToMultidownloadFileList', () {
    test('works with empty folder', () async {
      DriveDao mockDriveDao = MockDriveDao();
      final output = await convertFolderToMultidownloadFileList(
          mockDriveDao,
          FolderNode(
              folder: createMockFolderEntry(), subfolders: [], files: {}));

      expect(output.length, 0);
    });

    test('works with folder with files', () async {
      DriveDao mockDriveDao = MockDriveDao();
      final output =
          await convertFolderToMultidownloadFileList(mockDriveDao, mockFolderA);

      expect(output.length, 2);
      expect(output[0].txId, 'b0');
      expect(output[0].size, 75);
      expect(output[0].fileName, 'a/b/b0.txt');

      expect(output[1].txId, 'a0');
      expect(output[1].size, 85);
      expect(output[1].fileName, 'a/a0.txt');
    });
  });

  group('convertSelectionToMultiDownloadFileList', () {
    test('works with selection of only files', () async {
      DriveDao mockDriveDao = MockDriveDao();
      final selectedItems = [
        createMockFileDataTableItem(dataTxId: '1', size: 50),
        createMockFileDataTableItem(dataTxId: '2', size: const GiB(3).size),
        createMockFileDataTableItem(dataTxId: '3', size: 20),
      ];
      final output = await convertSelectionToMultiDownloadFileList(
          mockDriveDao, selectedItems);

      expect(output.length, 3);
      expect(output[0].txId, '1');
      expect(output[0].size, 50);
      expect(output[1].txId, '2');
      expect(output[1].size, const GiB(3).size);
      expect(output[2].txId, '3');
      expect(output[2].size, 20);
    });

    test('works with selection of files and nested folders', () async {
      DriveDao mockDriveDao = MockDriveDao();
      when(() => mockDriveDao.getFolderTree(any(), any()))
          .thenAnswer((_) async => mockFolderA);

      final selectedItems = [
        createMockFolderDataTableItem(name: 'abc'),
        createMockFileDataTableItem(dataTxId: '1', size: 50),
        createMockFileDataTableItem(dataTxId: '2', size: const GiB(3).size),
      ];
      final output = await convertSelectionToMultiDownloadFileList(
          mockDriveDao, selectedItems);

      expect(output.length, 4);
      expect(output[0].txId, 'b0');
      expect(output[0].size, 75);
      expect(output[0].fileName, 'a/b/b0.txt');

      expect(output[1].txId, 'a0');
      expect(output[1].size, 85);
      expect(output[1].fileName, 'a/a0.txt');

      expect(output[2].txId, '1');
      expect(output[2].size, 50);
      expect(output[3].txId, '2');
      expect(output[3].size, const GiB(3).size);
    });
  });
}
