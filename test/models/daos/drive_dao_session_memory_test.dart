import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/models/database/database_helpers.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/utils.dart';

/// What the drive DAO keeps in memory rather than in a table, and that it goes
/// at logout with everything else.
void main() {
  late Database db;
  late DriveDao driveDao;

  setUp(() {
    db = getTestDb();
    driveDao = db.driveDao;
  });

  tearDown(() => db.close());

  test('a drive key stored the moment the DAO exists is kept', () async {
    // No wait for the vaults: the constructor starts creating them and cannot
    // await, so the DAO has to wait for them itself.
    final fresh = getTestDb();
    addTearDown(fresh.close);

    await fresh.driveDao.putDriveKeyInMemory(
      driveID: 'drive',
      driveKey: DriveKey(SecretKey([1, 2, 3]), false),
    );

    expect(await fresh.driveDao.getDriveKeyFromMemory('drive'), isNotNull);
  });

  test('previewed bytes come back while they fit', () async {
    await driveDao.putPreviewDataInMemory(
      dataTxId: 'tx',
      bytes: Uint8List.fromList([1, 2, 3]),
      session: driveDao.previewSession,
    );

    expect(await driveDao.getPreviewDataFromMemory('tx'), [1, 2, 3]);
  });

  test('logout forgets drive keys and previewed bytes', () async {
    await driveDao.putDriveKeyInMemory(
      driveID: 'shared-private-drive',
      driveKey: DriveKey(SecretKey([1, 2, 3]), false),
    );
    await driveDao.putPreviewDataInMemory(
      dataTxId: 'tx',
      bytes: Uint8List.fromList([1, 2, 3]),
      session: driveDao.previewSession,
    );

    await DatabaseHelpers(db).clearSessionMemory();

    // A key to a shared private drive used to outlive the logout that was
    // supposed to end the session, until the tab closed.
    expect(
        await driveDao.getDriveKeyFromMemory('shared-private-drive'), isNull);
    expect(await driveDao.getPreviewDataFromMemory('tx'), isNull);
  });

  test('bytes fetched before a logout are not kept after it', () async {
    // A preview download that was in flight when the session ended.
    final startedIn = driveDao.previewSession;

    await DatabaseHelpers(db).clearSessionMemory();

    await driveDao.putPreviewDataInMemory(
      dataTxId: 'tx',
      bytes: Uint8List.fromList([1, 2, 3]),
      session: startedIn,
    );

    expect(await driveDao.getPreviewDataFromMemory('tx'), isNull);

    // The next session's own fetches are kept as before.
    await driveDao.putPreviewDataInMemory(
      dataTxId: 'tx',
      bytes: Uint8List.fromList([4, 5, 6]),
      session: driveDao.previewSession,
    );

    expect(await driveDao.getPreviewDataFromMemory('tx'), [4, 5, 6]);
  });
}
