import 'package:ardrive/blocs/fs_entry_info/fs_entry_info_cubit.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/utils.dart';

/// The details of a file, as a new version of it is uploaded on this device.
///
/// The upload writes the file row and a revision in one transaction, and the
/// panel re-reads the file when its row changes. It kept showing the first
/// version's metadata transaction: the new reading compared equal to the old
/// one, so it was never emitted.
void main() {
  const driveId = 'drive';
  const fileId = 'file';

  late Database db;

  setUp(() => db = getTestDb());
  tearDown(() => db.close());

  Future<void> uploadVersion({
    required int size,
    required String metadataTxId,
    required DateTime createdAt,
    required String action,
  }) async {
    final entity = FileEntity(
      id: fileId,
      driveId: driveId,
      parentFolderId: 'folder',
      name: 'notes.txt',
      dataTxId: 'data-$metadataTxId',
      size: size,
      lastModifiedDate: DateTime.utc(2026),
      dataContentType: 'text/plain',
    )
      ..txId = metadataTxId
      ..createdAt = createdAt;

    // As the upload writes it.
    await db.driveDao.transaction(() async {
      await db.driveDao.writeFileEntity(entity);
      await db.driveDao.insertFileRevision(
        entity.toRevisionCompanion(performedAction: action),
      );
    });
  }

  FsEntryInfoCubit cubit() => FsEntryInfoCubit(
        driveId: driveId,
        maybeSelectedItem: FileDataTableItem(
          driveId: driveId,
          fileId: fileId,
          parentFolderId: 'folder',
          name: 'notes.txt',
          size: 640,
          lastUpdated: DateTime.utc(2026),
          dateCreated: DateTime.utc(2026),
          lastModifiedDate: DateTime.utc(2026),
          contentType: 'text/plain',
          dataTxId: 'data-meta-1',
          metadataTx: null,
          dataTx: null,
          pinnedDataOwnerAddress: null,
          index: 0,
          isOwner: true,
        ),
        driveDao: db.driveDao,
        licenseService: MockLicenseService(),
        arweave: MockArweaveService(),
      );

  Future<FsEntryFileInfoSuccess> next(FsEntryInfoCubit info, String txId) =>
      info.stream
          .where((s) => s is FsEntryFileInfoSuccess && s.metadataTxId == txId)
          .cast<FsEntryFileInfoSuccess>()
          .first
          .timeout(const Duration(seconds: 5));

  test('shows a new version, with its own transaction and date', () async {
    final first = DateTime.utc(2026, 10, 20, 1, 44, 47);
    final second = DateTime.utc(2026, 10, 20, 1, 46, 35);

    await uploadVersion(
      size: 640,
      metadataTxId: 'meta-1',
      createdAt: first,
      action: RevisionAction.create,
    );

    final info = cubit();
    addTearDown(info.close);
    await next(info, 'meta-1');

    final updated = next(info, 'meta-2');
    await uploadVersion(
      size: 918,
      metadataTxId: 'meta-2',
      createdAt: second,
      action: RevisionAction.uploadNewVersion,
    );

    expect((await updated).lastUpdated.toUtc(), second);
  });

  // A state equal to the last one is not emitted, so a new transaction alone
  // has to make it a different state.
  test('a new transaction alone is a different state', () {
    FsEntryFileInfoSuccess state(String txId) => FsEntryFileInfoSuccess(
          name: 'notes.txt',
          lastUpdated: DateTime.utc(2026),
          dateCreated: DateTime.utc(2026),
          metadataTxId: txId,
          licenseState: null,
        );

    expect(state('meta-1'), isNot(state('meta-2')));
    expect(state('meta-1'), state('meta-1'));
  });
}
