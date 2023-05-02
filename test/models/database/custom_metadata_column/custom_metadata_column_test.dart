import 'package:ardrive/models/database/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../../test_utils/utils.dart';

void main() {
  group('The custom_metadata column', () {
    final db = getTestDb();

    group('for the drive_revisions table', () {
      final revisionWithNoCustomMetadata = DriveRevisionsCompanion.insert(
        driveId: 'driveId-no-custom-metadata',
        rootFolderId: 'rootFolderId',
        ownerAddress: 'ownerAddress',
        name: 'name',
        privacy: 'public',
        metadataTxId: 'metadataTxId',
        action: 'action',
      );
      final revisionWithCustomMetadata = DriveRevisionsCompanion.insert(
          driveId: 'driveId-custom-metadata',
          rootFolderId: 'rootFolderId',
          ownerAddress: 'ownerAddress',
          name: 'name',
          privacy: 'privacy',
          metadataTxId: 'metadataTxId',
          action: 'action',
          customJsonMetaData: const Value<String>('{"Custom": "Metadata"}'));

      test('can write one with no custom metadata', () {
        final dbFuture = db.driveDao.insertDriveRevision(
          revisionWithNoCustomMetadata,
        );
        expect(dbFuture, completes);
      });

      test('can read the previously written entry', () async {
        final driveRevisionsTable = db.driveRevisions;

        final selectStatement = db.select(driveRevisionsTable)
          ..where(
            (driveRevision) =>
                driveRevision.driveId.equals('driveId-no-custom-metadata'),
          );

        final revision = await selectStatement.getSingle();

        expect(revision, isA<DriveRevision>());
        expect(revision.customJsonMetaData, isNull);
      });

      test('can write one with custom metadata', () {
        final dbFuture = db.driveDao.insertDriveRevision(
          revisionWithCustomMetadata,
        );
        expect(dbFuture, completes);
      });

      test('can read the previously written entry', () async {
        final driveRevisionsTable = db.driveRevisions;

        final selectStatement = db.select(driveRevisionsTable)
          ..where(
            (driveRevision) =>
                driveRevision.driveId.equals('driveId-custom-metadata'),
          );

        final revision = await selectStatement.getSingle();

        expect(revision, isA<DriveRevision>());
        expect(revision.customJsonMetaData, isNotNull);
        expect(revision.customJsonMetaData, equals('{"Custom": "Metadata"}'));
      });
    });
  });
}
