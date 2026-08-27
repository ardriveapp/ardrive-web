// Prints the measurements the findings document quotes.
// ignore_for_file: avoid_print

/// The assertions behind `docs/drive-state/ATTACH_VFS_PROTOTYPE.md`, written
/// once and run on both platforms.
///
/// The VM run proves the SQL is right. The browser run is the one that decides
/// D12, because "does `ATTACH` work in the browser's virtual filesystem" is the
/// question the whole proposal rests on, and this repository has never
/// exercised a second database on web.
///
/// Both runs execute this identical file. A check that passed on one platform
/// and not the other would be exactly the finding worth having.
library;

import 'dart:typed_data';

import 'package:sqlite3/common.dart';
import 'package:test/test.dart';

import 'artifact_pipeline.dart';

typedef DatabaseOpener = CommonDatabase Function(String path);

/// A value planted in `profiles` that must never reach an artifact. Long and
/// unmistakable so that finding it in a byte array cannot be a coincidence.
const plantedSecret = 'PE9205-ENCRYPTED-WALLET-MUST-NEVER-BE-PUBLISHED';

const testDriveId = '0a36156c-6274-41a2-87b0-372f4da7f568';

/// Builds a database shaped like the app's: the two tables an artifact copies
/// from, plus the `profiles` table §2.1 says must never travel.
void createSourceDatabase(CommonDatabase db, {int fileRows = 500}) {
  db.execute('CREATE TABLE profiles ('
      'id TEXT NOT NULL, encryptedWallet TEXT NOT NULL, keySalt BLOB NOT NULL)');
  db.execute('CREATE TABLE drives ('
      'id TEXT NOT NULL, name TEXT, ownerAddress TEXT NOT NULL, '
      'privacy TEXT NOT NULL, rootFolderId TEXT NOT NULL, '
      'encryptedKey BLOB, keyEncryptionIv BLOB, lastBlockHeight INTEGER)');
  db.execute('CREATE TABLE file_revisions ('
      'fileId TEXT NOT NULL, driveId TEXT NOT NULL, name TEXT NOT NULL, '
      'parentFolderId TEXT NOT NULL, size INTEGER NOT NULL, '
      'lastModifiedDate INTEGER NOT NULL, dataContentType TEXT, '
      'metadataTxId TEXT NOT NULL, dataTxId TEXT NOT NULL, '
      'dateCreated INTEGER NOT NULL, action TEXT NOT NULL, '
      'isHidden INTEGER NOT NULL)');

  db.execute('INSERT INTO profiles VALUES (?, ?, ?)',
      ['profile-1', plantedSecret, Uint8List.fromList(List.filled(32, 7))]);
  db.execute(
    'INSERT INTO drives VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [
      testDriveId,
      'A private drive',
      'owner-address-under-test',
      'private',
      'root-folder-id',
      Uint8List.fromList(List.filled(32, 9)), // encryptedKey — must not travel
      Uint8List.fromList(List.filled(12, 3)), // keyEncryptionIv — likewise
      1814228,
    ],
  );

  final stmt = db.prepare('INSERT INTO file_revisions VALUES '
      '(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
  for (var i = 0; i < fileRows; i++) {
    stmt.execute([
      'file-$i',
      testDriveId,
      'document_$i.pdf',
      'folder-${i % 17}',
      1000 + i,
      1639422086000 + i * 1000,
      'application/pdf',
      'metadata-tx-$i',
      'data-tx-$i',
      1639422086000 + i * 1000,
      'create',
      0,
    ]);
  }
  stmt.dispose();
}

/// Creates the destination tables an importing client would already have.
void createTargetDatabase(CommonDatabase db) {
  db.execute('CREATE TABLE drives ('
      'id TEXT NOT NULL, name TEXT, ownerAddress TEXT NOT NULL, '
      'privacy TEXT NOT NULL, rootFolderId TEXT NOT NULL, '
      'encryptedKey BLOB, keyEncryptionIv BLOB, lastBlockHeight INTEGER)');
  db.execute('CREATE TABLE file_revisions ('
      'fileId TEXT NOT NULL, driveId TEXT NOT NULL, name TEXT NOT NULL, '
      'parentFolderId TEXT NOT NULL, size INTEGER NOT NULL, '
      'lastModifiedDate INTEGER NOT NULL, dataContentType TEXT, '
      'metadataTxId TEXT NOT NULL, dataTxId TEXT NOT NULL, '
      'dateCreated INTEGER NOT NULL, action TEXT NOT NULL, '
      'isHidden INTEGER NOT NULL)');
}

bool bytesContain(Uint8List haystack, String needle) {
  final n = needle.codeUnits;
  outer:
  for (var i = 0; i + n.length <= haystack.length; i++) {
    for (var j = 0; j < n.length; j++) {
      if (haystack[i + j] != n[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// [platform] names the run in test output. [pathFor] maps a bare name onto
/// whatever this platform calls a path. [reset] clears any state between tests.
void runAttachPrototypeSuite({
  required String platform,
  required DatabaseOpener open,
  required ByteReader readBytes,
  required ByteWriter writeBytes,
  required String Function(String name) pathFor,
  required void Function() reset,
}) {
  group('[$platform] D12 prototype', () {
    setUp(reset);

    test('case 1: ATTACH builds an artifact, and its bytes come back out',
        () {
      final source = open(pathFor('source.db'));
      createSourceDatabase(source);

      final bytes = buildArtifact(
        source,
        artifactPath: pathFor('artifact.db'),
        driveId: testDriveId,
        version: '1.0',
        blockEnd: 1814228,
        readBytes: readBytes,
      );
      source.dispose();

      // A SQLite file, and a non-trivial one.
      expect(bytes.length, greaterThan(4096));
      expect(String.fromCharCodes(bytes.sublist(0, 15)), 'SQLite format 3');
    });

    test('case 2: a received artifact ATTACHes and merges with INSERT…SELECT',
        () {
      final source = open(pathFor('source.db'));
      createSourceDatabase(source);
      final bytes = buildArtifact(
        source,
        artifactPath: pathFor('artifact.db'),
        driveId: testDriveId,
        version: '1.0',
        blockEnd: 1814228,
        readBytes: readBytes,
      );
      source.dispose();

      final target = open(pathFor('target.db'));
      createTargetDatabase(target);

      final merged = importArtifact(
        target,
        bytes,
        artifactPath: pathFor('received.db'),
        expectedVersion: '1.0',
        expectedDriveId: testDriveId,
        writeBytes: writeBytes,
      );

      expect(merged, 500);
      expect(
        target.select('SELECT count(*) AS c FROM file_revisions').single['c'],
        500,
      );
      expect(
        target.select('SELECT name FROM file_revisions WHERE fileId = ?',
            ['file-42']).single['name'],
        'document_42.pdf',
      );
      expect(
        target.select('SELECT privacy FROM drives').single['privacy'],
        'private',
      );
      target.dispose();
    });

    test('the artifact carries no key material, because none was ever written',
        () {
      final source = open(pathFor('source.db'));
      createSourceDatabase(source);
      final bytes = buildArtifact(
        source,
        artifactPath: pathFor('artifact.db'),
        driveId: testDriveId,
        version: '1.0',
        blockEnd: 1814228,
        readBytes: readBytes,
      );
      source.dispose();

      expect(bytesContain(bytes, plantedSecret), isFalse,
          reason: 'profiles.encryptedWallet reached the artifact');
      expect(bytesContain(bytes, 'profiles'), isFalse,
          reason: 'the word "profiles" appears in the artifact at all');
      expect(bytesContain(bytes, 'encryptedKey'), isFalse,
          reason: 'the drives projection leaked a withheld column name');
    });

    test('tear-down leaks the secret whenever secure_delete is off', () {
      // The obvious implementation is to copy the whole database and then
      // delete what must not ship. This test is why D12 does not do that.
      //
      // SQLite reclaims dropped pages to the freelist. Whether it *zeroes*
      // them first is decided by `secure_delete`, a per-connection pragma
      // whose compiled-in default varies by build — so the safety of
      // tear-down is not a property of the code, it is a property of whichever
      // SQLite the client happens to be running. Measured here rather than
      // assumed, on both platforms, because they are different builds.
      final probe = open(pathFor('probe.db'));
      final platformDefault =
          probe.select('PRAGMA secure_delete').single.values.first;
      probe.dispose();
      printOnFailure('$platform secure_delete default = $platformDefault');

      final source = open(pathFor('source.db'));
      source.execute('PRAGMA secure_delete = 0');
      createSourceDatabase(source);
      source.execute('DROP TABLE profiles');
      source.dispose();

      expect(
        bytesContain(readBytes(pathFor('source.db')), plantedSecret),
        isTrue,
        reason: 'With secure_delete off, DROP TABLE left the wallet ciphertext '
            'in the file. That is the failure D12 removes by never writing it.',
      );
    });

    test('the platform default for secure_delete is recorded, not relied on',
        () {
      final db = open(pathFor('probe.db'));
      final value = db.select('PRAGMA secure_delete').single.values.first;
      db.dispose();
      // No assertion on the value: the point is that D12 must hold whatever
      // it is. Printed so the prototype's findings can quote it per platform.
      print('[$platform] PRAGMA secure_delete default = $value');
      expect(value, anyOf(0, 1, 2));
    });

    test('the pipeline holds at 20,000 rows, with no row becoming an object',
        () {
      // Not a memory measurement — a browser test cannot take one. What it
      // does show is that both halves are pure SQL at size: no Dart object is
      // constructed per row anywhere in `artifact_pipeline.dart`, so whatever
      // SQLite's page cache costs is the whole cost.
      final source = open(pathFor('source.db'));
      createSourceDatabase(source, fileRows: 20000);

      final built = DateTime.now();
      final bytes = buildArtifact(
        source,
        artifactPath: pathFor('artifact.db'),
        driveId: testDriveId,
        version: '1.0',
        blockEnd: 1814228,
        readBytes: readBytes,
      );
      final buildMs = DateTime.now().difference(built).inMilliseconds;
      source.dispose();

      final target = open(pathFor('target.db'));
      createTargetDatabase(target);
      final imported = DateTime.now();
      final merged = importArtifact(
        target,
        bytes,
        artifactPath: pathFor('received.db'),
        expectedVersion: '1.0',
        expectedDriveId: testDriveId,
        writeBytes: writeBytes,
      );
      final importMs = DateTime.now().difference(imported).inMilliseconds;

      expect(merged, 20000);
      expect(
        target.select('SELECT count(*) AS c FROM file_revisions').single['c'],
        20000,
      );
      target.dispose();

      print('[$platform] 20k rows: artifact ${bytes.length} B, '
          'build $buildMs ms, import $importMs ms');
    }, timeout: const Timeout(Duration(minutes: 3)));

    group('the read gate refuses', () {
      late Uint8List good;

      setUp(() {
        final source = open(pathFor('source.db'));
        createSourceDatabase(source);
        good = buildArtifact(
          source,
          artifactPath: pathFor('artifact.db'),
          driveId: testDriveId,
          version: '1.0',
          blockEnd: 1814228,
          readBytes: readBytes,
        );
        source.dispose();
      });

      Uint8List tamper(void Function(CommonDatabase db) change) {
        writeBytes(pathFor('tampered.db'), good);
        final db = open(pathFor('tampered.db'));
        change(db);
        db.dispose();
        return readBytes(pathFor('tampered.db'));
      }

      void expectRejected(Uint8List bytes, ArtifactRejection reason) {
        final target = open(pathFor('target.db'));
        createTargetDatabase(target);
        expect(
          () => importArtifact(
            target,
            bytes,
            artifactPath: pathFor('received.db'),
            expectedVersion: '1.0',
            expectedDriveId: testDriveId,
            writeBytes: writeBytes,
          ),
          throwsA(isA<ArtifactRejected>()
              .having((e) => e.reason, 'reason', reason)),
        );
        // Nothing was written before the refusal.
        expect(
          target.select('SELECT count(*) AS c FROM file_revisions').single['c'],
          0,
        );
        target.dispose();
      }

      test('a view — the classic hostile-schema vector', () {
        expectRejected(
          tamper((db) => db.execute(
              'CREATE VIEW sneaky AS SELECT * FROM file_revisions')),
          ArtifactRejection.unexpectedSchema,
        );
      });

      test('a trigger', () {
        expectRejected(
          tamper((db) => db.execute('CREATE TRIGGER t AFTER INSERT ON meta '
              'BEGIN DELETE FROM file_revisions; END')),
          ArtifactRejection.unexpectedSchema,
        );
      });

      test('an extra table', () {
        expectRejected(
          tamper((db) => db.execute('CREATE TABLE extra (x TEXT)')),
          ArtifactRejection.unexpectedSchema,
        );
      });

      test('an entity count that disagrees with the body', () {
        expectRejected(
          tamper((db) => db.execute('UPDATE meta SET entityCount = 9999')),
          ArtifactRejection.entityCountMismatch,
        );
      });

      test('a drive id that is not the one being synced', () {
        expectRejected(
          tamper((db) => db.execute("UPDATE meta SET driveId = 'other-drive'")),
          ArtifactRejection.driveIdMismatch,
        );
      });

      test('a version this reader does not implement', () {
        expectRejected(
          tamper((db) => db.execute("UPDATE meta SET version = '2.0'")),
          ArtifactRejection.versionMismatch,
        );
      });
    });
  });
}
