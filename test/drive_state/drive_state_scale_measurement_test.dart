@Tags(['measurement'])
library;

import 'dart:convert';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:ardrive/drive_state/data/drive_state_export.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/utils.dart';

/// Weighs the real wire format at the size of the user's actual drive.
///
/// Not a committed test — a measurement, run to replace the modelled figures
/// in the proposal with observed ones.
void main() {
  const driveId = 'measured-drive';
  const rootFolderId = 'measured-root';
  const fileCount = 41767;
  const folderCount = 120;
  // 4.7% of entities carry a second revision, per the real drive.
  const secondRevisionEvery = 21;

  /// Arweave ids and uuids are the incompressible part of this payload, and
  /// they dominate it: three transaction ids and two uuids per file. Synthetic
  /// ids built by interpolating a counter gzip almost perfectly and would
  /// flatter the result by several times over, so these are drawn from a
  /// seeded PRNG at the real entropy - 32 bytes for a transaction id, 16 for a
  /// uuid.
  final rng = Random(20260819);
  const b64 =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  String txId() => List.generate(43, (_) => b64[rng.nextInt(64)]).join();
  String uuid() {
    String hex(int n) =>
        List.generate(n, (_) => '0123456789abcdef'[rng.nextInt(16)]).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
  }

  /// Human file names, varied but not random - real names repeat words, which
  /// is why they compress where ids do not.
  const nouns = [
    'invoice',
    'photo',
    'scan',
    'render',
    'export',
    'backup',
    'contract',
    'draft',
    'final',
    'notes',
    'screenshot',
    'recording'
  ];
  const exts = ['.jpeg', '.png', '.pdf', '.mp4', '.zip', '.json'];

  test('weighs a 42k-file drive through the real export', () async {
    final db = getTestDb();
    addTearDown(db.close);

    final created = DateTime(2024, 3, 1, 12);

    await db.batch((b) {
      b.insert(
        db.drives,
        DrivesCompanion.insert(
          id: driveId,
          rootFolderId: rootFolderId,
          ownerAddress: 'a-realistic-looking-arweave-wallet-address-43chars',
          name: 'my drive',
          privacy: DrivePrivacyTag.private,
        ),
      );
      b.insert(
        db.driveRevisions,
        DriveRevisionsCompanion.insert(
          driveId: driveId,
          rootFolderId: rootFolderId,
          name: 'my drive',
          privacy: DrivePrivacyTag.private,
          metadataTxId: txId(),
          ownerAddress: 'a-realistic-looking-arweave-wallet-address-43chars',
          dateCreated: Value(created),
          action: RevisionAction.create,
        ),
      );

      final folderIds = <String>[];
      for (var f = 0; f < folderCount; f++) {
        final id = uuid();
        folderIds.add(id);
        b.insert(
          db.folderEntries,
          FolderEntriesCompanion.insert(
            id: id,
            driveId: driveId,
            parentFolderId: const Value(rootFolderId),
            name: 'Some Folder Name $f',
            path: '/Some Folder Name $f',
            lastUpdated: Value(created),
            dateCreated: Value(created),
          ),
        );
        b.insert(
          db.folderRevisions,
          FolderRevisionsCompanion.insert(
            folderId: id,
            driveId: driveId,
            name: 'Some Folder Name $f',
            parentFolderId: const Value(rootFolderId),
            metadataTxId: txId(),
            dateCreated: Value(created),
            action: RevisionAction.create,
          ),
        );
      }

      for (var i = 0; i < fileCount; i++) {
        final id = uuid();
        final parent = folderIds[i % folderCount];
        final name = '${nouns[rng.nextInt(nouns.length)]}-'
            '${nouns[rng.nextInt(nouns.length)]}-$i'
            '${exts[rng.nextInt(exts.length)]}';
        final dataTx = txId();

        b.insert(
          db.fileEntries,
          FileEntriesCompanion.insert(
            id: id,
            driveId: driveId,
            parentFolderId: parent,
            name: name,
            path: '/Some Folder Name ${i % folderCount}/$name',
            dataTxId: dataTx,
            size: 2400000 + i,
            lastModifiedDate: created,
            dateCreated: Value(created),
            lastUpdated: Value(created),
            dataContentType: const Value('image/jpeg'),
          ),
        );

        final revisions = i % secondRevisionEvery == 0 ? 2 : 1;
        for (var r = 0; r < revisions; r++) {
          b.insert(
            db.fileRevisions,
            FileRevisionsCompanion.insert(
              fileId: id,
              driveId: driveId,
              parentFolderId: parent,
              name: name,
              size: 2400000 + i,
              lastModifiedDate: created,
              metadataTxId: txId(),
              dataTxId: dataTx,
              dateCreated: Value(created.add(Duration(minutes: r))),
              dataContentType: const Value('image/jpeg'),
              action: RevisionAction.create,
            ),
          );
        }
      }
    });

    final exportWatch = Stopwatch()..start();
    final export = await exportDriveState(db.driveDao, driveId);
    exportWatch.stop();

    final encodeWatch = Stopwatch()..start();
    final json = jsonEncode(export.toJson());
    final plaintext = Uint8List.fromList(utf8.encode(json));
    encodeWatch.stop();

    final gzipWatch = Stopwatch()..start();
    final compressed = GZipEncoder().encode(plaintext)!;
    gzipWatch.stop();

    const mib = 1024 * 1024;
    final uncompressed = plaintext.lengthInBytes;
    final gz = compressed.length;

    // ignore: avoid_print
    print('''

=== MEASURED, real export at real scale ===
entities (Entity-Count)   ${export.entityCount}
file rows                 ${export.files.length}
file revisions            ${export.fileRevisions.length}
folder rows               ${export.folders.length}
folder revisions          ${export.folderRevisions.length}

uncompressed JSON         $uncompressed bytes = ${(uncompressed / mib).toStringAsFixed(2)} MiB
gzipped                   $gz bytes = ${(gz / mib).toStringAsFixed(2)} MiB
compression ratio         ${(uncompressed / gz).toStringAsFixed(2)}x

bytes per entity (uncomp) ${(uncompressed / export.entityCount).toStringAsFixed(0)}
GCM limit                 $maxSizeSupportedByGCMEncryption bytes = ${(maxSizeSupportedByGCMEncryption / mib).toStringAsFixed(0)} MiB
headroom                  ${(maxSizeSupportedByGCMEncryption / uncompressed).toStringAsFixed(2)}x
crossover at              ${(fileCount * maxSizeSupportedByGCMEncryption / uncompressed).round()} files

export                    ${exportWatch.elapsedMilliseconds} ms
jsonEncode + utf8         ${encodeWatch.elapsedMilliseconds} ms
gzip                      ${gzipWatch.elapsedMilliseconds} ms
=== END ===
''');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
