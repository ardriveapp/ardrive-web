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

      expect(output.length, 1);
      expect(output[0] is MultiDownloadFolder, true);
      final folder = output[0] as MultiDownloadFolder;
      expect(folder.folderPath, 'name/');
    });

    test('works with folder with files', () async {
      DriveDao mockDriveDao = MockDriveDao();
      final output =
          await convertFolderToMultidownloadFileList(mockDriveDao, mockFolderA);

      expect(output.length, 4);

      expect(output[0] is MultiDownloadFolder, true);
      expect((output[0] as MultiDownloadFolder).folderPath, 'a/');

      expect(output[1] is MultiDownloadFolder, true);
      expect((output[1] as MultiDownloadFolder).folderPath, 'a/b/');

      expect(output[2] is MultiDownloadFile, true);
      var file = output[2] as MultiDownloadFile;
      expect(file.txId, 'b0');
      expect(file.size, 75);
      expect(file.fileName, 'a/b/b0.txt');

      expect(output[3] is MultiDownloadFile, true);
      file = output[3] as MultiDownloadFile;
      expect(file.txId, 'a0');
      expect(file.size, 85);
      expect(file.fileName, 'a/a0.txt');
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
      final output = (await convertSelectionToMultiDownloadFileList(
              mockDriveDao, selectedItems))
          .whereType<MultiDownloadFile>()
          .toList();

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
      final output = (await convertSelectionToMultiDownloadFileList(
          mockDriveDao, selectedItems));

      expect(output.length, 6);
      expect(output[0] is MultiDownloadFolder, true);
      expect((output[0] as MultiDownloadFolder).folderPath, 'a/');

      expect(output[1] is MultiDownloadFolder, true);
      expect((output[1] as MultiDownloadFolder).folderPath, 'a/b/');

      expect(output[2] is MultiDownloadFile, true);
      var file = output[2] as MultiDownloadFile;
      expect(file.txId, 'b0');
      expect(file.size, 75);
      expect(file.fileName, 'a/b/b0.txt');

      expect(output[3] is MultiDownloadFile, true);
      file = output[3] as MultiDownloadFile;
      expect(file.txId, 'a0');
      expect(file.size, 85);
      expect(file.fileName, 'a/a0.txt');

      expect(output[4] is MultiDownloadFile, true);
      file = output[4] as MultiDownloadFile;
      expect(file.txId, '1');
      expect(file.size, 50);
      expect(output[5] is MultiDownloadFile, true);
      file = output[5] as MultiDownloadFile;
      expect(file.txId, '2');
      expect(file.size, const GiB(3).size);
    });
  });
}
