import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/utils.dart';

/// The explorer's License column (#51): hidden unless something in the drive
/// is licensed, and the reader's own choice wins either way.
void main() {
  group('showsLicenseColumn', () {
    test('is hidden when nothing in the drive is licensed', () {
      expect(
        DriveDetailCubit.showsLicenseColumn(
          columnVisibility: const {},
          driveHasLicensedFiles: false,
        ),
        isFalse,
      );
    });

    test('shows when something in the drive is licensed', () {
      expect(
        DriveDetailCubit.showsLicenseColumn(
          columnVisibility: const {},
          driveHasLicensedFiles: true,
        ),
        isTrue,
      );
    });

    test('follows the reader\'s choice over the drive', () {
      expect(
        DriveDetailCubit.showsLicenseColumn(
          columnVisibility: const {DriveDetailCubit.licenseColumnIndex: true},
          driveHasLicensedFiles: false,
        ),
        isTrue,
      );
      expect(
        DriveDetailCubit.showsLicenseColumn(
          columnVisibility: const {DriveDetailCubit.licenseColumnIndex: false},
          driveHasLicensedFiles: true,
        ),
        isFalse,
      );
    });
  });

  group('DriveDao.driveHasLicensedFiles', () {
    late Database db;

    setUp(() => db = getTestDb());
    tearDown(() => db.close());

    Future<void> addFile(String driveId, String id, {String? licenseTxId}) =>
        db.into(db.fileEntries).insert(
              FileEntriesCompanion.insert(
                id: id,
                driveId: driveId,
                parentFolderId: '$driveId-root',
                name: id,
                dataTxId: '$id-tx',
                size: 1,
                lastModifiedDate: DateTime(2024, 1, 1),
                path: '',
                licenseTxId: Value(licenseTxId),
              ),
            );

    test('is false for a drive with no licensed file', () async {
      await addFile('drive-a', 'a1');

      expect(await db.driveDao.driveHasLicensedFiles('drive-a'), isFalse);
    });

    test('is true once one file carries a license', () async {
      await addFile('drive-a', 'a1');
      await addFile('drive-a', 'a2', licenseTxId: 'license-tx');

      expect(await db.driveDao.driveHasLicensedFiles('drive-a'), isTrue);
    });

    test('asks of this drive only', () async {
      await addFile('drive-b', 'b1', licenseTxId: 'license-tx');

      expect(await db.driveDao.driveHasLicensedFiles('drive-a'), isFalse);
    });
  });
}
