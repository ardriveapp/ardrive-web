import 'package:ardrive/models/models.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two ways this app counts what a drive holds, and why they must agree.
///
/// Reported as a drive showing the same file count but a different total GB
/// between sessions. The drives list counts `file_entries` directly; the
/// profile dropdown used `filesInDriveWithRevisionTransactions`, which
/// inner-joins each file to the metadata and data transactions of its latest
/// revision. A file whose transaction rows have not synced yet is dropped from
/// that join entirely - so the profile total omitted both the file and its
/// bytes, and grew as those rows landed.
void main() {
  late Database db;

  setUp(() => db = Database(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> addDrive(String id, {String owner = 'me'}) =>
      db.into(db.drives).insert(
            DrivesCompanion.insert(
              id: id,
              rootFolderId: '$id-root',
              ownerAddress: owner,
              name: id,
              privacy: DrivePrivacyTag.public,
            ),
          );

  Future<void> addFile(
    String driveId,
    String fileId, {
    required int size,
    bool withTransactions = true,
  }) async {
    await db.into(db.fileEntries).insert(
          FileEntriesCompanion.insert(
            id: fileId,
            driveId: driveId,
            name: fileId,
            parentFolderId: '$driveId-root',
            path: '/$fileId',
            size: size,
            lastModifiedDate: DateTime(2024),
            dataTxId: '$fileId-data',
          ),
        );
  }

  test('a file whose transactions have not synced still counts', () async {
    await addDrive('drive-a');
    await addFile('drive-a', 'file-1', size: 1000, withTransactions: false);

    final summaries = await db.driveDao.driveContentSummaries();

    expect(
      summaries['drive-a']?.fileCount,
      1,
      reason: 'the file is in the local tables, so it is one of the files this '
          'device holds',
    );
    expect(
      summaries['drive-a']?.totalSize,
      1000,
      reason: 'its bytes count whether or not its transaction rows have '
          'arrived - dropping them is what made the same drive report a '
          'different total between sessions',
    );
  });

  /// And the query the profile total used to rely on drops it, which is the
  /// whole of the bug: the file is really there, and that query cannot see it.
  test('the revision-transaction join cannot see that file at all', () async {
    await addDrive('drive-a');
    await addFile('drive-a', 'file-1', size: 1000);

    final joined = await db.driveDao
        .filesInDriveWithRevisionTransactions(driveId: 'drive-a')
        .get();

    expect(
      joined,
      isEmpty,
      reason: 'no revision rows, so the inner join matches nothing - counting '
          'this way omits the file and its bytes until a sync fills those '
          'rows in, and reports a larger total each time it does',
    );
  });

  /// Whose storage the profile line is describing.
  ///
  /// A drive somebody else shared is readable here and is not this account's
  /// storage. Counting it made the line describe what the reader can see
  /// rather than what they are keeping - and one shared drive of a million
  /// files would have dwarfed everything they own.
  test('a drive somebody else owns is not this account\'s storage', () async {
    await addDrive('mine');
    await addDrive('theirs', owner: 'somebody-else');
    await addFile('mine', 'file-1', size: 1000);
    await addFile('theirs', 'file-2', size: 9999);

    final drives = await db.driveDao.allDrives().get();
    final summaries = await db.driveDao.driveContentSummaries();

    // The filter the profile line applies.
    final owned = drives.where((drive) => drive.ownerAddress == 'me').toList();

    var totalSize = 0;
    for (final drive in owned) {
      totalSize += summaries[drive.id]?.totalSize ?? 0;
    }

    expect(owned.map((d) => d.id), ['mine']);
    expect(
      totalSize,
      1000,
      reason: "the shared drive's bytes belong to whoever owns it",
    );
  });
}
