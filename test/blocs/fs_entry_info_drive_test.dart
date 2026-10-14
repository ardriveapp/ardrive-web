import 'package:ardrive/blocs/fs_entry_info/fs_entry_info_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/utils.dart';

/// The details of a drive, before and after this device has read it.
///
/// Reading the drive list stores each drive and a placeholder for its root
/// folder, and nothing else. The panel used to ask for the root folder's
/// revision with `getSingle`, which threw for such a drive inside a stream
/// listener - where no `onError` hears it - and so waited on a spinner that
/// could never finish. That is what More Info on any never-synced drive did.
void main() {
  const driveId = 'drive';
  const rootFolderId = 'root';

  late Database db;

  setUp(() async {
    db = getTestDb();

    // What reading the drive list leaves behind.
    await db.batch((batch) {
      batch.insert(
        db.drives,
        DrivesCompanion.insert(
          id: driveId,
          rootFolderId: rootFolderId,
          ownerAddress: 'owner',
          name: 'Photos',
          privacy: DrivePrivacyTag.private,
        ),
      );
      batch.insert(
        db.folderEntries,
        FolderEntriesCompanion.insert(
          id: rootFolderId,
          driveId: driveId,
          name: 'Photos',
          isHidden: const Value(false),
          path: '',
        ),
      );
    });
  });

  tearDown(() => db.close());

  FsEntryInfoCubit cubit() => FsEntryInfoCubit(
        driveId: driveId,
        maybeSelectedItem: DriveDataItem(
          id: driveId,
          driveId: driveId,
          name: 'Photos',
          lastUpdated: DateTime(2026),
          dateCreated: DateTime(2026),
          index: 0,
          isOwner: true,
        ),
        driveDao: db.driveDao,
        licenseService: MockLicenseService(),
        arweave: MockArweaveService(),
      );

  test('a drive known only from the drive list says so', () async {
    final info = cubit();
    addTearDown(info.close);

    final state = await info.stream.first;

    expect(state, isA<FsEntryUnsyncedDriveInfo>());
    expect((state as FsEntryUnsyncedDriveInfo).drive.name, 'Photos');
  });

  /// A root folder that has been read, but no drive revision: `getSingle`
  /// throws. The panel must finish on the failure, not spin.
  test('a load that fails ends in failure, not a spinner', () async {
    await db.into(db.folderRevisions).insert(
          FolderRevisionsCompanion.insert(
            folderId: rootFolderId,
            driveId: driveId,
            name: 'Photos',
            metadataTxId: 'tx',
            action: RevisionAction.create,
          ),
        );

    final info = cubit();
    addTearDown(info.close);

    expect(await info.stream.first, isA<FsEntryInfoFailure>());
  });
}
