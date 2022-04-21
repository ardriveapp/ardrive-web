import 'package:ardrive/blocs/data_export/data_export_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:test/test.dart';

import '../snapshots/data_export_snapshot.dart';
import '../test_utils/utils.dart';

void main() {
  late Database db;
  late DriveDao driveDao;

  group('DataExport', () {
    const driveId = 'drive-id';
    const rootFolderId = 'root-folder-id';
    const rootFolderFileCount = 5;

    const nestedFolderId = 'nested-folder-id';
    const nestedFolderFileCount = 5;

    const emptyNestedFolderIdPrefix = 'empty-nested-folder-id';
    const emptyNestedFolderCount = 5;

    const testGatewayURL = 'https://arweave.net';
    setUp(() async {
      db = getTestDb();
      driveDao = db.driveDao;
      // Setup mock drive.
      await addTestFilesToDb(
        db,
        driveId: driveId,
        emptyNestedFolderCount: emptyNestedFolderCount,
        emptyNestedFolderIdPrefix: emptyNestedFolderIdPrefix,
        rootFolderId: rootFolderId,
        rootFolderFileCount: rootFolderFileCount,
        nestedFolderId: nestedFolderId,
        nestedFolderFileCount: nestedFolderFileCount,
      );
    });
    tearDown(() async {
      await db.close();
    });

    blocTest<DataExportCubit, DataExportState>(
        'export drive contents as csv file exports the correct number of files',
        build: () => DataExportCubit(
              gatewayURL: testGatewayURL,
              driveDao: driveDao,
              driveId: driveId,
            ),
        act: (cubit) async => await cubit.exportData(),
        expect: () => [
              TypeMatcher<DataExportInProgress>(),
              TypeMatcher<DataExportSuccess>()
            ],
        verify: (cubit) async {
          final state = cubit.state as DataExportSuccess;
          expect(
            (await state.file.readAsString()),
            equals(dataExportSnapshot),
          );
        });
  });
}
