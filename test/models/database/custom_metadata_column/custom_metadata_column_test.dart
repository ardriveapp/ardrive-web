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

    group('for the folder_revisions table', () {
      final folderWithNoCustomMetadata = FolderRevisionsCompanion.insert(
        folderId: 'folderId-no-custom-metadata',
        driveId: 'driveId',
        parentFolderId: const Value<String>('parentFolderId'),
        name: 'name',
        action: 'action',
        metadataTxId: 'metadataTxId',
      );
      final folderWithCustomMetadata = FolderRevisionsCompanion.insert(
        folderId: 'folderId-custom-metadata',
        driveId: 'driveId',
        parentFolderId: const Value<String>('parentFolderId'),
        name: 'name',
        action: 'action',
        metadataTxId: 'metadataTxId',
        customJsonMetaData: const Value<String>('{"Custom": "Metadata"}'),
      );

      test('can write one with no custom metadata', () {
        final dbFuture =
            db.driveDao.insertFolderRevision(folderWithNoCustomMetadata);
        expect(dbFuture, completes);
      });

      test('can read the previously written entry', () async {
        final folderRevisionsTable = db.folderRevisions;

        final selectStatement = db.select(folderRevisionsTable)
          ..where(
            (folderRevision) =>
                folderRevision.folderId.equals('folderId-no-custom-metadata'),
          );

        final revision = await selectStatement.getSingle();

        expect(revision, isA<FolderRevision>());
        expect(revision.customJsonMetaData, isNull);
      });

      test('can write one with custom metadata', () {
        final dbFuture =
            db.driveDao.insertFolderRevision(folderWithCustomMetadata);
        expect(dbFuture, completes);
      });

      test('can read the previously written entry', () async {
        final folderRevisionsTable = db.folderRevisions;

        final selectStatement = db.select(folderRevisionsTable)
          ..where(
            (folderRevision) =>
                folderRevision.folderId.equals('folderId-custom-metadata'),
          );

        final revision = await selectStatement.getSingle();

        expect(revision, isA<FolderRevision>());
        expect(revision.customJsonMetaData, isNotNull);
        expect(revision.customJsonMetaData, equals('{"Custom": "Metadata"}'));
      });
    });

    group('for the file_revisions table', () {
      final fileWithNoCustomMetadata = FileRevisionsCompanion.insert(
        fileId: 'fileId-no-custom-metadata',
        driveId: 'driveId',
        name: 'name',
        action: 'action',
        metadataTxId: 'metadataTxId',
        size: 0,
        dataTxId: 'dataTxId',
        lastModifiedDate: DateTime(1234),
        parentFolderId: 'parentFolderId',
      );
      final fileWithCustomMetadata = FileRevisionsCompanion.insert(
        fileId: 'fileId-custom-metadata',
        driveId: 'driveId',
        name: 'name',
        action: 'action',
        metadataTxId: 'metadataTxId',
        size: 0,
        dataTxId: 'dataTxId',
        lastModifiedDate: DateTime(1234),
        parentFolderId: 'parentFolderId',
        customJsonMetaData: const Value<String>('{"Custom": "Metadata"}'),
      );

      test('can write one with no custom metadata', () {
        final dbFuture =
            db.driveDao.insertFileRevision(fileWithNoCustomMetadata);
        expect(dbFuture, completes);
      });

      test('can read the previously written entry', () async {
        final fileRevisionsTable = db.fileRevisions;

        final selectStatement = db.select(fileRevisionsTable)
          ..where(
            (fileRevision) =>
                fileRevision.fileId.equals('fileId-no-custom-metadata'),
          );

        final revision = await selectStatement.getSingle();

        expect(revision, isA<FileRevision>());
        expect(revision.customJsonMetaData, isNull);
      });

      test('can write one with custom metadata', () {
        final dbFuture = db.driveDao.insertFileRevision(fileWithCustomMetadata);
        expect(dbFuture, completes);
      });

      test('can read the previously written entry', () async {
        final fileRevisionsTable = db.fileRevisions;

        final selectStatement = db.select(fileRevisionsTable)
          ..where(
            (fileRevision) =>
                fileRevision.fileId.equals('fileId-custom-metadata'),
          );

        final revision = await selectStatement.getSingle();

        expect(revision, isA<FileRevision>());
        expect(revision.customJsonMetaData, isNotNull);
        expect(revision.customJsonMetaData, equals('{"Custom": "Metadata"}'));
      });
    });
  });
}
