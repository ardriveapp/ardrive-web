import 'package:ardrive/blocs/data_export/data_export_cubit.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:moor/moor.dart';
import 'package:test/test.dart';

import '../utils/utils.dart';

void main() {
  late Database db;
  late DriveDao driveDao;
  late ArweaveService arweave;

  late DataExportCubit dataExportCubit;

  group('DataExport', () {
    const driveId = 'drive-id';
    const rootFolderId = 'root-folder-id';
    const rootFolderFileCount = 5;

    const nestedFolderId = 'nested-folder-id';
    const nestedFolderFileCount = 5;

    const emptyNestedFolderIdPrefix = 'empty-nested-folder-id';
    const emptyNestedFolderCount = 5;

    setUp(() async {
      db = getTestDb();
      driveDao = db.driveDao;
      final configService = ConfigService();
      final config = await configService.getConfig();

      arweave = ArweaveService(
          Arweave(gatewayUrl: Uri.parse(config.defaultArweaveGatewayUrl!)));

      // Setup mock drive.
      await db.batch((batch) {
        batch.insert(
          db.drives,
          DrivesCompanion.insert(
            id: driveId,
            rootFolderId: rootFolderId,
            ownerAddress: 'owner-address',
            name: 'drive-name',
            privacy: DrivePrivacy.public,
          ),
        );

        batch.insertAll(
          db.folderEntries,
          [
            FolderEntriesCompanion.insert(
                id: rootFolderId,
                driveId: driveId,
                name: 'drive-name',
                path: ''),
            FolderEntriesCompanion.insert(
                id: nestedFolderId,
                driveId: driveId,
                parentFolderId: Value(rootFolderId),
                name: nestedFolderId,
                path: '/$nestedFolderId'),
            ...List.generate(
              emptyNestedFolderCount,
              (i) {
                final folderId = '$emptyNestedFolderIdPrefix$i';
                return FolderEntriesCompanion.insert(
                  id: folderId,
                  driveId: driveId,
                  parentFolderId: Value(rootFolderId),
                  name: folderId,
                  path: '/$folderId',
                );
              },
            )..shuffle(),
          ],
        );

        batch.insertAll(
          db.fileEntries,
          [
            ...List.generate(
              rootFolderFileCount,
              (i) {
                final fileId = '$rootFolderId$i';
                return FileEntriesCompanion.insert(
                  id: fileId,
                  driveId: driveId,
                  parentFolderId: rootFolderId,
                  name: fileId,
                  path: '/$fileId',
                  dataTxId: '',
                  size: 500,
                  lastModifiedDate: DateTime.now(),
                  dataContentType: Value(''),
                );
              },
            )..shuffle(),
            ...List.generate(
              nestedFolderFileCount,
              (i) {
                final fileId = '$nestedFolderId$i';
                return FileEntriesCompanion.insert(
                  id: fileId,
                  driveId: driveId,
                  parentFolderId: nestedFolderId,
                  name: fileId,
                  path: '/$nestedFolderId/$fileId',
                  dataTxId: '',
                  size: 500,
                  lastModifiedDate: DateTime.now(),
                  dataContentType: Value(''),
                );
              },
            )..shuffle(),
          ],
        );
      });
    });

    tearDown(() async {
      await db.close();
    });

    test('csv contains the correct data', () async {
      dataExportCubit = DataExportCubit(
        arweave: arweave,
        driveDao: driveDao,
        driveId: 'drive-id',
      );
    });
  });
}
