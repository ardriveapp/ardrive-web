import 'dart:convert';

import 'package:ardrive/drive_state/data/drive_state_export.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:drift/drift.dart';
import 'package:test/test.dart';

import '../../test_utils/utils.dart';

void main() {
  late Database db;

  setUp(() => db = getTestDb());
  tearDown(() => db.close());

  group('the export projection against the live schema', () {
    // The failure this guards against is not this projection being wrong
    // today — it is a future migration widening what an exporter sees. A
    // column added to `drives` lands in neither list, so this test fails and
    // whoever added it has to say whether it may be published. schemaVersion
    // is 29 and moves regularly.
    void expectProjectionCoversTable(TableInfo table) {
      final classified = [
        ...driveStateExportedColumns(table),
        ...driveStateWithheldColumns(table),
      ].map((c) => c.name);

      expect(
        classified.toSet(),
        equals(table.$columns.map((c) => c.name).toSet()),
        reason: 'every column of ${table.actualTableName} must be classified '
            'as exported or withheld',
      );
      expect(
        classified.length,
        classified.toSet().length,
        reason: 'no column of ${table.actualTableName} may be both',
      );
    }

    test('classifies every column of drives', () {
      expectProjectionCoversTable(db.drives);
    });

    test('classifies every column of folder_entries', () {
      expectProjectionCoversTable(db.folderEntries);
    });

    test('classifies every column of file_entries', () {
      expectProjectionCoversTable(db.fileEntries);
    });

    test('withholds the drive key and everything needed to unwrap it', () {
      expect(
        driveStateWithheldColumns(db.drives).map((c) => c.name).toSet(),
        containsAll(<String>{
          'encryptedKey',
          'driveKeyGenerated',
          'keyEncryptionIv',
        }),
      );
      expect(
        driveStateExportedColumns(db.drives).map((c) => c.name),
        isNot(anyElement(isIn(<String>{
          'encryptedKey',
          'driveKeyGenerated',
          'keyEncryptionIv',
        }))),
      );
    });
  });

  group('exportDriveState', () {
    const driveId = 'drive-id';
    const rootFolderId = 'root-folder-id';
    const nestedFolderId = 'nested-folder-id';

    setUp(() async {
      await addTestFilesToDb(
        db,
        driveId: driveId,
        rootFolderId: rootFolderId,
        nestedFolderId: nestedFolderId,
        emptyNestedFolderCount: 3,
        emptyNestedFolderIdPrefix: 'empty-nested-folder-id',
        rootFolderFileCount: 4,
        nestedFolderFileCount: 2,
      );
    });

    test('reads the drive row, its folders and its files', () async {
      final export = await exportDriveState(db.driveDao, driveId);

      expect(export.drive.id, driveId);
      expect(export.drive.rootFolderId, rootFolderId);
      expect(export.folders.map((f) => f.id), contains(rootFolderId));
      // root + nested + 3 empty
      expect(export.folders, hasLength(5));
      expect(export.files, hasLength(6));
      expect(export.entityCount, 12);
      expect(
        export.files.every((f) => f.driveId == driveId),
        isTrue,
      );
    });

    test('carries no key material even when the drive holds some', () async {
      await db.update(db.drives).write(
            DrivesCompanion(
              encryptedKey: Value(Uint8List.fromList([1, 2, 3, 4])),
              keyEncryptionIv: Value(Uint8List.fromList([5, 6, 7])),
              driveKeyGenerated: const Value(true),
            ),
          );

      final export = await exportDriveState(db.driveDao, driveId);
      final encoded = jsonEncode(export.toJson());

      for (final field in ['encryptedKey', 'keyEncryptionIv', 'driveKeyGenerated']) {
        expect(encoded, isNot(contains(field)));
      }
      // The bytes themselves, base64 or otherwise, must not appear either.
      expect(encoded, isNot(contains('AQIDBA')));
    });

    test('reads only the named drive', () async {
      const otherDriveId = 'other-drive-id';
      await addTestFilesToDb(
        db,
        driveId: otherDriveId,
        rootFolderId: 'other-root-folder-id',
        nestedFolderId: 'other-nested-folder-id',
        emptyNestedFolderCount: 1,
        emptyNestedFolderIdPrefix: 'other-empty-',
        rootFolderFileCount: 1,
        nestedFolderFileCount: 1,
      );

      final export = await exportDriveState(db.driveDao, driveId);

      expect(export.folders.every((f) => f.driveId == driveId), isTrue);
      expect(export.files.every((f) => f.driveId == driveId), isTrue);
    });

    test('orders rows by id so two exports of one state agree', () async {
      final first = await exportDriveState(db.driveDao, driveId);
      final second = await exportDriveState(db.driveDao, driveId);

      expect(
        first.folders.map((f) => f.id).toList(),
        equals(List.of(first.folders.map((f) => f.id))..sort()),
      );
      expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
    });

    test('refuses a drive that is not there', () {
      expect(
        () => exportDriveState(db.driveDao, 'no-such-drive'),
        throwsA(isA<StateError>()),
      );
    });

    test('round-trips through JSON to an identical object graph', () async {
      final export = await exportDriveState(db.driveDao, driveId);

      final decoded = DriveStateExport.fromJson(
        jsonDecode(jsonEncode(export.toJson())) as Map<String, dynamic>,
      );

      expect(decoded, equals(export));
      expect(decoded.drive, equals(export.drive));
      expect(decoded.folders, equals(export.folders));
      expect(decoded.files, equals(export.files));
    });

    test('round-trips nullable columns that are actually set', () async {
      await db.update(db.fileEntries).write(
            const FileEntriesCompanion(
              licenseTxId: Value('license-tx'),
              bundledIn: Value('bundle-tx'),
              thumbnail: Value('{"variants":[]}'),
              pinnedDataOwnerAddress: Value('pinned-owner'),
              customJsonMetadata: Value('{"a":1}'),
              customGQLTags: Value('[{"name":"a"}]'),
              assignedNames: Value('["name"]'),
              fallbackTxId: Value('fallback-tx'),
              originalOwner: Value('original-owner'),
              importSource: Value('import-source'),
            ),
          );
      await db.update(db.drives).write(
            const DrivesCompanion(
              syncCursor: Value('cursor'),
              lastBlockHeight: Value(1814228),
              signatureType: Value('1'),
              bundledIn: Value('drive-bundle'),
              customJsonMetadata: Value('{"b":2}'),
            ),
          );

      final export = await exportDriveState(db.driveDao, driveId);
      final decoded = DriveStateExport.fromJson(
        jsonDecode(jsonEncode(export.toJson())) as Map<String, dynamic>,
      );

      expect(decoded, equals(export));
      expect(decoded.files.first.licenseTxId, 'license-tx');
    });

  group('columns that are not secret but must not travel', () {
    /// Neither is key material, so neither is caught by the leak test above -
    /// they are withheld for correctness instead.
    ///
    /// `syncCursor` is an opaque cursor issued by one gateway's indexer and
    /// means nothing to another, so an importer adopting it would resume
    /// pagination from an arbitrary position.
    ///
    /// `lastBlockHeight` is the producer's watermark, which is a different
    /// claim from the artifact's coverage. Adopting one that sits above the
    /// artifact's Block-End would have a client believe it had synced a range
    /// the artifact never contained - the drive watermark advancing past
    /// unsynced entities, which is the silent drop in
    /// SYNC_SKIPPED_ENTITY_PERSISTENCE.md. Coverage comes from the tag.
    test('the drive sync cursor and watermark are withheld', () async {
      final db = getTestDb();
      addTearDown(db.close);
      await addTestFilesToDb(
        db,
        driveId: driveId,
        rootFolderId: rootFolderId,
        nestedFolderId: 'nested',
        emptyNestedFolderCount: 0,
        emptyNestedFolderIdPrefix: 'empty',
        rootFolderFileCount: 1,
        nestedFolderFileCount: 0,
      );
      await db.driveDao.writeToDrive(const DrivesCompanion(
        id: Value(driveId),
        syncCursor: Value('an-endpoint-specific-cursor'),
        lastBlockHeight: Value(1814228),
      ));

      final encoded = jsonEncode((await exportDriveState(db.driveDao, driveId))
          .toJson());

      expect(encoded, isNot(contains('syncCursor')));
      expect(encoded, isNot(contains('an-endpoint-specific-cursor')));
      expect(encoded, isNot(contains('lastBlockHeight')));
      expect(encoded, isNot(contains('1814228')));
    });
  });
  });

  group('DriveStateExport.fromJson', () {
    // Built through a JSON round trip so the maps and lists have the same
    // dynamic types a real payload arrives with, rather than the tighter ones
    // Dart infers for a literal.
    Map<String, dynamic> minimalPayload() => jsonDecode(jsonEncode({
          'version': driveStateFormatVersion,
          'sections': {
            'drives': {
              'rows': [
                {
                  'id': 'drive-id',
                  'rootFolderId': 'root-folder-id',
                  'ownerAddress': 'owner',
                  'name': 'a drive',
                  'syncCursor': null,
                  'lastBlockHeight': null,
                  'privacy': DrivePrivacyTag.private,
                  'bundledIn': null,
                  'customJsonMetadata': null,
                  'customGQLTags': null,
                  'isHidden': false,
                  'signatureType': null,
                  'dateCreated': 1000,
                  'lastUpdated': 2000,
                },
              ],
            },
            'folder_entries': {'rows': []},
            'file_entries': {'rows': []},
          },
        })) as Map<String, dynamic>;

    test('ignores a section it does not know', () {
      final payload = minimalPayload();
      (payload['sections'] as Map)['aggregate_totals'] = {
        'rows': [
          {'whatever': 1},
        ],
      };

      expect(DriveStateExport.fromJson(payload).drive.id, 'drive-id');
    });

    test('ignores a field it does not know', () {
      final payload = minimalPayload();
      final driveRow = ((payload['sections'] as Map)['drives']
          as Map)['rows'] as List;
      (driveRow.single as Map)['somethingNew'] = 'ignored';

      expect(DriveStateExport.fromJson(payload).drive.name, 'a drive');
    });

    test('treats an absent section as empty', () {
      final payload = minimalPayload();
      (payload['sections'] as Map).remove('file_entries');

      expect(DriveStateExport.fromJson(payload).files, isEmpty);
    });

    test('rejects a version it could misread, with a distinct reason', () {
      final payload = minimalPayload()
        ..['version'] = driveStateFormatVersion + 1;

      expect(
        () => DriveStateExport.fromJson(payload),
        throwsA(
          isA<DriveStateFormatException>().having(
            (e) => e.error,
            'error',
            DriveStateFormatError.unsupportedVersion,
          ),
        ),
      );
    });

    test('rejects a missing required field as malformed', () {
      final payload = minimalPayload();
      final driveRow = ((payload['sections'] as Map)['drives']
          as Map)['rows'] as List;
      (driveRow.single as Map).remove('ownerAddress');

      expect(
        () => DriveStateExport.fromJson(payload),
        throwsA(
          isA<DriveStateFormatException>().having(
            (e) => e.error,
            'error',
            DriveStateFormatError.malformed,
          ),
        ),
      );
    });

    test('rejects a payload without exactly one drive row', () {
      final payload = minimalPayload();
      ((payload['sections'] as Map)['drives'] as Map)['rows'] = [];

      expect(
        () => DriveStateExport.fromJson(payload),
        throwsA(isA<DriveStateFormatException>()),
      );
    });
  });
}
