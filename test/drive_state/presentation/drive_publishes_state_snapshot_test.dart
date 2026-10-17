import 'package:ardrive/components/create_snapshot_dialog.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/utils.dart';

/// Whether "Create snapshot" makes a drive state artifact, asked of the drive
/// that was clicked.
///
/// It used to be asked of `DriveDetailCubit`, which describes the drive and
/// folder on screen. From the list of drives no drive is open, so every drive
/// got the older snapshot; inside a drive, an empty subfolder did too. These
/// tests pin that the answer depends on the clicked drive's own rows and
/// nothing else. The combinations of the four conditions themselves are
/// `drive_state_publish_offer_test.dart`.
void main() {
  const owner = 'owner-address';

  late Database db;

  setUp(() => db = getTestDb());
  tearDown(() async => db.close());

  Future<void> addFolder(
    String driveId,
    String folderId, {
    required String? parentFolderId,
  }) =>
      db.into(db.folderEntries).insert(
            FolderEntriesCompanion.insert(
              id: folderId,
              driveId: driveId,
              parentFolderId: Value(parentFolderId),
              name: folderId,
              path: '',
            ),
          );

  Future<Drive> addDrive(String id, {String ownerAddress = owner}) async {
    await db.into(db.drives).insert(
          DrivesCompanion.insert(
            id: id,
            rootFolderId: '$id-root',
            ownerAddress: ownerAddress,
            name: id,
            privacy: DrivePrivacyTag.public,
          ),
        );
    await addFolder(id, '$id-root', parentFolderId: null);
    return db.driveDao.driveById(driveId: id).getSingle();
  }

  Future<void> addFile(String driveId, String parentFolderId) =>
      db.into(db.fileEntries).insert(
            FileEntriesCompanion.insert(
              id: '$driveId-file',
              driveId: driveId,
              parentFolderId: parentFolderId,
              name: 'file',
              dataTxId: '$driveId-tx',
              size: 1,
              lastModifiedDate: DateTime(2024),
              path: '',
            ),
          );

  Future<bool> offered(
    Drive drive, {
    bool publishingEnabled = true,
    String? walletAddress = owner,
  }) =>
      drivePublishesStateSnapshot(
        drive: drive,
        publishingEnabled: publishingEnabled,
        walletAddress: walletAddress,
        driveDao: db.driveDao,
      );

  test('is offered for an owned drive with a file in it', () async {
    final drive = await addDrive('a');
    await addFile('a', 'a-root');

    expect(await offered(drive), isTrue);
  });

  test('is offered for an owned drive with only a folder in it', () async {
    final drive = await addDrive('a');
    await addFolder('a', 'a-sub', parentFolderId: 'a-root');

    expect(await offered(drive), isTrue);
  });

  // The explorer's version of the bug: the folder on screen is empty, the
  // drive is not.
  test('counts a file anywhere in the drive, not only in its root', () async {
    final drive = await addDrive('a');
    await addFolder('a', 'a-full', parentFolderId: 'a-root');
    await addFolder('a', 'a-empty', parentFolderId: 'a-root');
    await addFile('a', 'a-full');

    expect(await offered(drive), isTrue);
  });

  test('is not offered for a drive with nothing but its root', () async {
    final drive = await addDrive('a');

    expect(await offered(drive), isFalse);
  });

  // The drives list's version: the answer is about the clicked drive, so
  // another drive's contents cannot lend it any.
  test('does not count another drive\'s contents', () async {
    final empty = await addDrive('empty');
    await addDrive('full');
    await addFile('full', 'full-root');

    expect(await offered(empty), isFalse);
  });

  test('is not offered where publishing is off', () async {
    final drive = await addDrive('a');
    await addFile('a', 'a-root');

    expect(await offered(drive, publishingEnabled: false), isFalse);
  });

  test('is not offered for a drive another wallet owns', () async {
    final drive = await addDrive('a', ownerAddress: 'someone else');
    await addFile('a', 'a-root');

    expect(await offered(drive), isFalse);
  });

  test('is not offered when nobody is logged in', () async {
    final drive = await addDrive('a');
    await addFile('a', 'a-root');

    expect(await offered(drive, walletAddress: null), isFalse);
  });
}
