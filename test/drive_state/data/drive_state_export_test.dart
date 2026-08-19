import 'dart:convert';

import 'package:ardrive/drive_state/data/drive_state_export.dart';
import 'package:ardrive/entities/entities.dart';
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

    // Driven off `driveStateExportedTables` rather than a list of table names
    // written out here, so that a section added for a fourth table is
    // classified before it can ship: naming the tables twice is how a guard
    // ends up covering three of them while the export reads four.
    test('classifies every column of every exported table', () {
      final tables = driveStateExportedTables(db);

      expect(tables, isNotEmpty);
      for (final table in tables) {
        expectProjectionCoversTable(table);
      }
    });

    /// The artifact covers one drive and is encrypted with that one drive's
    /// key, so every table it reads has to be answerable to "which drive is
    /// this row about". The neighbouring tables that look exportable —
    /// `network_transactions`, `arns_records`, `ant_records` — have no
    /// `driveId` at all, and publishing one would hand everyone holding this
    /// drive's key a list of the user's other drives.
    test('every exported table can be scoped to one drive', () {
      for (final table in driveStateExportedTables(db)) {
        final columns = table.$columns.map((c) => c.name);

        // `drives` is the one drive; it is scoped by its own primary key.
        final scopingColumn =
            table.actualTableName == driveSectionName ? 'id' : 'driveId';

        expect(
          columns,
          contains(scopingColumn),
          reason: '${table.actualTableName} has no $scopingColumn, so its '
              'rows cannot be limited to the drive being exported',
        );
      }
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

  /// The most important promise the export makes is about the tables it will
  /// not read, and a promise nothing asserts is a promise the next refactor
  /// keeps by luck.
  group('tables the export refuses', () {
    void expectRefused(TableInfo table) {
      expect(
        () => driveStateExportedColumns(table),
        throwsA(isA<ArgumentError>()),
        reason: '${table.actualTableName} must not be exportable',
      );
      expect(
        () => driveStateWithheldColumns(table),
        throwsA(isA<ArgumentError>()),
        reason: '${table.actualTableName} must not be exportable',
      );
    }

    test('refuses profiles, which holds the wallet', () {
      expectRefused(db.profiles);
    });

    test('refuses the revision tables', () {
      // Read for existence, never for content: decision D2 is current state
      // only, and a revision carries metadata transaction ids that say
      // nothing the current row does not.
      expectRefused(db.driveRevisions);
      expectRefused(db.folderRevisions);
      expectRefused(db.fileRevisions);
    });

    test('refuses every table it does not export', () {
      final exported =
          driveStateExportedTables(db).map((t) => t.actualTableName).toSet();

      final refused = db.allTables
          .where((t) => !exported.contains(t.actualTableName))
          .toList();

      expect(refused, isNotEmpty);
      for (final table in refused) {
        expectRefused(table);
      }
    });
  });

  group('exportDriveState', () {
    const driveId = 'drive-id';
    const rootFolderId = 'root-folder-id';
    const nestedFolderId = 'nested-folder-id';
    const emptyFolderIdPrefix = 'empty-nested-folder-id';

    final syncedFolderIds = [
      rootFolderId,
      nestedFolderId,
      ...List.generate(3, (i) => '$emptyFolderIdPrefix$i'),
    ];

    setUp(() async {
      await addTestFilesToDb(
        db,
        driveId: driveId,
        rootFolderId: rootFolderId,
        nestedFolderId: nestedFolderId,
        emptyNestedFolderCount: 3,
        emptyNestedFolderIdPrefix: emptyFolderIdPrefix,
        rootFolderFileCount: 4,
        nestedFolderFileCount: 2,
      );
      // `addTestFilesToDb` writes file revisions but no folder ones, which
      // would make every folder read as a local stand-in. This is a drive
      // whose folders all synced.
      await addFolderRevisionsToDb(
        db,
        driveId: driveId,
        folderIds: syncedFolderIds,
      );
    });

    test('reads the drive row, its folders and its files', () async {
      final export = await exportDriveState(db.driveDao, driveId);

      expect(export.drive.id, driveId);
      expect(export.drive.rootFolderId, rootFolderId);
      expect(export.folders.map((f) => f.id), contains(rootFolderId));
      // root + nested + 3 empty
      expect(export.folders.map((f) => f.id).toSet(), syncedFolderIds.toSet());
      expect(export.folders, hasLength(5));
      expect(export.files, hasLength(6));
      expect(export.entityCount, 12);
      expect(
        export.files.every((f) => f.driveId == driveId),
        isTrue,
      );
    });

    test('carries no key material even when the drive holds some', () async {
      // High entropy on purpose: short byte strings collide with ordinary
      // text, and a leak has to be caught in whatever encoding it takes.
      final encryptedKey = Uint8List.fromList([
        0x8f, 0x2b, 0xd4, 0x61, 0x9c, 0x07, 0xa3, 0x5e, //
        0x13, 0xf0, 0x6d, 0xba, 0x47, 0x91, 0xce, 0x25,
      ]);
      final keyEncryptionIv = Uint8List.fromList([
        0x5a, 0xe3, 0x1c, 0x76, 0xb8, 0x04, //
        0xdf, 0x92, 0x30, 0xa7, 0x6b, 0xfe,
      ]);

      await db.update(db.drives).write(
            DrivesCompanion(
              encryptedKey: Value(encryptedKey),
              keyEncryptionIv: Value(keyEncryptionIv),
              driveKeyGenerated: const Value(true),
            ),
          );

      final export = await exportDriveState(db.driveDao, driveId);
      final encoded = jsonEncode(export.toJson());

      for (final field in [
        'encryptedKey',
        'keyEncryptionIv',
        'driveKeyGenerated'
      ]) {
        expect(encoded, isNot(contains(field)));
      }

      // The bytes themselves, in both shapes they could take. Drift's default
      // serializer passes a `Uint8List` through untransformed, so a leak
      // through a generated `toJson()` renders as a JSON array of ints, which
      // a base64 assertion alone would sail straight past.
      for (final bytes in [encryptedKey, keyEncryptionIv]) {
        expect(encoded, isNot(contains(base64.encode(bytes))));
        expect(encoded, isNot(contains(bytes.join(','))));
      }
    });

    /// What the assertions above test is one rendering of one value; what
    /// actually keeps key material out of the artifact is the shape of the
    /// query — a `selectOnly` that names every column it reads, so a column
    /// added by a later migration is invisible until someone classifies it.
    /// So assert the SQL.
    test('the statements it runs name no withheld column', () {
      final withheld = <String>{
        for (final table in driveStateExportedTables(db))
          ...driveStateWithheldColumns(table).map((c) => c.name),
      };
      expect(withheld, contains('encryptedKey'));

      final statements = {
        driveSectionName: driveStateDriveQuery(db.driveDao, driveId),
        folderEntriesSectionName:
            driveStateFolderEntriesQuery(db.driveDao, driveId),
        fileEntriesSectionName:
            driveStateFileEntriesQuery(db.driveDao, driveId),
      };

      statements.forEach((section, statement) {
        final sql = statement.constructQuery().sql;

        for (final column in withheld) {
          expect(
            sql,
            isNot(contains(column)),
            reason: 'the $section query reads $column',
          );
        }

        // A star select would publish whatever the next migration adds.
        expect(
          sql,
          isNot(contains('*')),
          reason: 'the $section query must name the columns it reads',
        );
      });

      // And what it does read is exactly the classified projection.
      statements.forEach((section, statement) {
        final sql = statement.constructQuery().sql;
        final table = driveStateExportedTables(db)
            .firstWhere((t) => t.actualTableName == section);

        for (final column in driveStateExportedColumns(table)) {
          expect(sql, contains(column.name));
        }
      });
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
      await addFolderRevisionsToDb(
        db,
        driveId: otherDriveId,
        folderIds: [
          'other-root-folder-id',
          'other-nested-folder-id',
          'other-empty-0',
        ],
      );

      final export = await exportDriveState(db.driveDao, driveId);

      expect(export.folders.every((f) => f.driveId == driveId), isTrue);
      expect(export.files.every((f) => f.driveId == driveId), isTrue);
      expect(export.folders, hasLength(5));
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

    test('claims coverage up to the drive\'s own watermark, and no further',
        () async {
      await db.driveDao.writeToDrive(const DrivesCompanion(
        id: Value(driveId),
        lastBlockHeight: Value(1814228),
      ));

      final export = await exportDriveState(db.driveDao, driveId);

      // The producer accounted for the drive as far as it had synced it, and
      // saying anything higher would be publishing the gap the coverage claim
      // exists to close.
      expect(export.coverage.blockStart, 0);
      expect(export.coverage.blockEnd, 1814228);
    });

    test('claims nothing for a drive that has never synced', () async {
      await db.driveDao.writeToDrive(const DrivesCompanion(
        id: Value(driveId),
        lastBlockHeight: Value.absent(),
      ));

      final export = await exportDriveState(db.driveDao, driveId);

      expect(export.coverage.blockEnd, 0);
    });

    test('carries the coverage claim inside the signed payload', () async {
      await db.driveDao.writeToDrive(const DrivesCompanion(
        id: Value(driveId),
        lastBlockHeight: Value(900),
      ));

      final json = (await exportDriveState(db.driveDao, driveId)).toJson();

      // Top level, beside the version: it is a claim about the whole payload,
      // not a property of any row, and it has to be in the bytes the owner
      // signs because a transaction tag is not.
      expect(json['coverage'], {'blockStart': 0, 'blockEnd': 900});
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

    /// The artifact is immutable, and the importer keeps a local row only
    /// when it is strictly newer than the published one. A row this client
    /// invented is stamped with *now*, so it is always newer than a real row
    /// carrying its revision's chain commit time — publishing one would
    /// overwrite a correctly synced folder in every client that imported it,
    /// with no way to take it back.
    group('rows this client invented never travel', () {
      test('a ghost folder is not exported', () async {
        // As `SyncRepository` writes one: named after its own uuid, parented
        // to the drive root, stamped now.
        await db.into(db.folderEntries).insert(
              FolderEntriesCompanion.insert(
                id: 'ghost-folder-id',
                driveId: driveId,
                name: 'ghost-folder-id',
                parentFolderId: const Value(rootFolderId),
                path: '',
                isGhost: const Value(true),
                lastUpdated: Value(DateTime.now()),
                dateCreated: Value(DateTime.now()),
              ),
            );

        final export = await exportDriveState(db.driveDao, driveId);

        expect(
          export.folders.map((f) => f.id),
          isNot(contains('ghost-folder-id')),
        );
        expect(export.folders, hasLength(5));
        expect(export.entityCount, 12);
      });

      test('a ghost that has since synced is exported', () async {
        await db.into(db.folderEntries).insert(
              FolderEntriesCompanion.insert(
                id: 'ghost-folder-id',
                driveId: driveId,
                name: 'ghost-folder-id',
                parentFolderId: const Value(rootFolderId),
                path: '',
                isGhost: const Value(true),
                lastUpdated: Value(DateTime.now()),
              ),
            );
        // Its real metadata lands. `isGhost` is not the discriminator — a
        // revision is — so the row travels now.
        await addFolderRevisionsToDb(
          db,
          driveId: driveId,
          folderIds: ['ghost-folder-id'],
        );

        final export = await exportDriveState(db.driveDao, driveId);

        expect(export.folders.map((f) => f.id), contains('ghost-folder-id'));
        expect(export.folders, hasLength(6));
        expect(export.entityCount, 13);
      });

      /// The root folder placeholder carries no marker at all — not
      /// `isGhost`, since the upsert that lands real metadata leaves absent
      /// columns alone and the flag would stick forever — so a filter on
      /// `isGhost` would publish it.
      test('a root folder placeholder is not exported', () async {
        const discoveredDriveId = 'discovered-drive-id';
        const discoveredRootFolderId = 'discovered-root-folder-id';

        // The real path: a drive found on chain gets a root folder row so it
        // can be opened before its metadata arrives.
        await db.driveDao.updateUserDrives({
          DriveEntity(
            id: discoveredDriveId,
            name: 'a discovered drive',
            rootFolderId: discoveredRootFolderId,
            privacy: DrivePrivacyTag.public,
            authMode: DriveAuthModeTag.none,
          )..ownerAddress = 'owner-address': null,
        }, null);

        final placeholder = await db.driveDao
            .folderById(folderId: discoveredRootFolderId)
            .getSingle();
        expect(placeholder.isGhost, isFalse,
            reason: 'the placeholder carries no marker of its own');

        final export = await exportDriveState(db.driveDao, discoveredDriveId);

        expect(export.folders, isEmpty);
        expect(export.files, isEmpty);
        expect(export.entityCount, 1);
      });

      test('the root folder is exported once its metadata syncs', () async {
        const discoveredDriveId = 'discovered-drive-id';
        const discoveredRootFolderId = 'discovered-root-folder-id';

        await db.driveDao.updateUserDrives({
          DriveEntity(
            id: discoveredDriveId,
            name: 'a discovered drive',
            rootFolderId: discoveredRootFolderId,
            privacy: DrivePrivacyTag.public,
            authMode: DriveAuthModeTag.none,
          )..ownerAddress = 'owner-address': null,
        }, null);
        await addFolderRevisionsToDb(
          db,
          driveId: discoveredDriveId,
          folderIds: [discoveredRootFolderId],
        );

        final export = await exportDriveState(db.driveDao, discoveredDriveId);

        expect(export.folders.map((f) => f.id), [discoveredRootFolderId]);
        expect(export.entityCount, 2);
      });

      test('a file with no revision is not exported', () async {
        await db.into(db.fileEntries).insert(
              FileEntriesCompanion.insert(
                id: 'unsynced-file-id',
                driveId: driveId,
                parentFolderId: rootFolderId,
                name: 'unsynced-file-id',
                dataTxId: 'unsynced-file-data',
                size: 500,
                lastModifiedDate: DateTime.now(),
                path: '',
              ),
            );

        final export = await exportDriveState(db.driveDao, driveId);

        expect(
          export.files.map((f) => f.id),
          isNot(contains('unsynced-file-id')),
        );
        expect(export.files, hasLength(6));
        expect(export.entityCount, 12);
      });
    });

    group('columns that are not secret but must not travel', () {
      /// Neither is key material, so neither is caught by the leak test above -
      /// they are withheld for correctness instead.
      ///
      /// `syncCursor` is an opaque cursor issued by one gateway's indexer and
      /// means nothing to another, so an importer adopting it would resume
      /// pagination from an arbitrary position.
      ///
      /// `lastBlockHeight` must not travel as a *column of the drive row*: a row
      /// column is adopted wholesale by the merge, unchecked against anything.
      /// The same integer does travel as the payload's coverage claim, which is
      /// a different thing - the importer refuses the artifact unless the
      /// `Block-End` tag agrees with it, and only then advances the watermark
      /// across ground the claim covers. A watermark adopted without those
      /// checks is the drive advancing past unsynced entities: the silent drop
      /// in SYNC_SKIPPED_ENTITY_PERSISTENCE.md.
      test('the drive sync cursor and watermark are withheld from the row',
          () async {
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

        final export = await exportDriveState(db.driveDao, driveId);
        final encoded = jsonEncode(export.toJson());
        final driveRow = jsonEncode(export.drive.toJson());

        expect(encoded, isNot(contains('syncCursor')));
        expect(encoded, isNot(contains('an-endpoint-specific-cursor')));
        expect(encoded, isNot(contains('lastBlockHeight')));
        // Not as a field of the drive row, under any name.
        expect(driveRow, isNot(contains('1814228')));
        // Only as the coverage claim, which is checked against the tags before
        // anything is done with it.
        expect(export.coverage.blockEnd, 1814228);
      });
    });
  });

  group('DriveStateExport.fromJson', () {
    // Built through a JSON round trip so the maps and lists have the same
    // dynamic types a real payload arrives with, rather than the tighter ones
    // Dart infers for a literal.
    Map<String, dynamic> minimalPayload() => jsonDecode(jsonEncode({
          'version': driveStateFormatVersion,
          'coverage': {'blockStart': 0, 'blockEnd': 900},
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
      final driveRow =
          ((payload['sections'] as Map)['drives'] as Map)['rows'] as List;
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
      final driveRow =
          ((payload['sections'] as Map)['drives'] as Map)['rows'] as List;
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

    test('reads the coverage claim', () {
      final export = DriveStateExport.fromJson(minimalPayload());

      expect(export.coverage.blockStart, 0);
      expect(export.coverage.blockEnd, 900);
    });

    test('rejects a payload with no coverage claim', () {
      // Not optional, and not defaulted. A reader that treated an absent
      // coverage claim as "believe the Block-End tag" would be the reader the
      // claim was added to remove.
      final payload = minimalPayload()..remove('coverage');

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

    test('rejects a coverage claim that is not a block range', () {
      for (final coverage in [
        {'blockStart': 900, 'blockEnd': 100},
        {'blockStart': -1, 'blockEnd': 900},
        {'blockStart': 0, 'blockEnd': -1},
        {'blockStart': 0},
        {'blockStart': 0, 'blockEnd': '900'},
      ]) {
        final payload = minimalPayload()..['coverage'] = coverage;

        expect(
          () => DriveStateExport.fromJson(payload),
          throwsA(
            isA<DriveStateFormatException>().having(
              (e) => e.error,
              'error',
              DriveStateFormatError.malformed,
            ),
          ),
          reason: '$coverage is not a coverage claim',
        );
      }
    });

    test('round-trips the coverage claim', () {
      final export = DriveStateExport.fromJson(minimalPayload());
      final again = DriveStateExport.fromJson(
        jsonDecode(jsonEncode(export.toJson())) as Map<String, dynamic>,
      );

      expect(again.coverage, export.coverage);
      expect(again, export);
    });

    test('two payloads that differ only in coverage are not equal', () {
      final export = DriveStateExport.fromJson(minimalPayload());
      final other = DriveStateExport.fromJson(
        minimalPayload()..['coverage'] = {'blockStart': 0, 'blockEnd': 901},
      );

      expect(other, isNot(equals(export)));
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
