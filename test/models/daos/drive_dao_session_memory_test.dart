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

  setUp(() async {
    db = getTestDb();
    driveDao = db.driveDao;
    // The vaults are created asynchronously by the constructor.
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() => db.close());

  test('previewed bytes come back while they fit', () async {
    await driveDao.putPreviewDataInMemory(
      dataTxId: 'tx',
      bytes: Uint8List.fromList([1, 2, 3]),
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
    );

    await DatabaseHelpers(db).clearSessionMemory();

    // A key to a shared private drive used to outlive the logout that was
    // supposed to end the session, until the tab closed.
    expect(await driveDao.getDriveKeyFromMemory('shared-private-drive'),
        isNull);
    expect(await driveDao.getPreviewDataFromMemory('tx'), isNull);
  });
}
