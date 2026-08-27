@Tags(['measurement'])
library;

import 'dart:convert';
import 'dart:io' show ProcessInfo;
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:ardrive/drive_state/domain/drive_state_format_version.dart';
import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_export.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
import 'package:ardrive/drive_state/domain/drive_state_outcome.dart';
import 'package:ardrive/drive_state/domain/drive_state_protection.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart'
    show maxSizeSupportedByGCMEncryption;
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart' show Wallet;
import 'package:cryptography/cryptography.dart' show AesGcm;
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/utils.dart';

/// The one version this build writes and reads. Tests follow the constant
/// rather than restating it, so moving the format version does not mean
/// editing every fixture — which is how a fixture ends up asserting a
/// version the code no longer speaks.
String get currentVersionString => DriveStateFormatVersion.current.toString();

/// Weighs the real wire format at the size of the user's actual drive, and
/// then carries that drive all the way through the pipeline it was built for.
///
/// Not committed assertions — measurements, run to replace the modelled
/// figures in the proposal with observed ones. Two tests rather than one:
///
///  * `weighs …` is the source of the size figures in
///    `docs/DRIVE_STATE_ARTIFACT.md` §1.1 and §2.3, and stops at gzip.
///  * `carries …` runs export → seal → import → the file list, at the same
///    scale, over the half of the pipeline that no other test exercises above
///    about ten rows.
///
/// The second is split off rather than appended so that a seal or an import
/// which blows up at scale — the thing it exists to find out — does not take
/// the size measurement down with it.
void main() {
  const driveId = 'measured-drive';
  const rootFolderId = 'measured-root';
  const driveName = 'my drive';
  const fileCount = 41767;
  const folderCount = 120;
  // 4.7% of entities carry a second revision, per the real drive.
  const secondRevisionEvery = 21;

  /// A plausible sync watermark. Non-zero on purpose:
  /// `DriveStateCreationService` refuses to publish a drive whose
  /// `lastBlockHeight` is 0, so a fixture left at the column default would be
  /// weighing an artifact that could never have been produced.
  const watermark = 1600000;

  /// Stands in for a real wallet address in the weighing test, where no wallet
  /// is generated. It reaches the payload through the two columns that carry
  /// an address — `drives.ownerAddress` and `drive_revisions.ownerAddress` —
  /// so a real 43 character address in its place moves the payload by 14
  /// bytes and nothing else.
  const placeholderOwner = 'a-realistic-looking-arweave-wallet-address-43chars';

  const mib = 1024 * 1024;

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

  /// Builds the measured drive in [db]: 41,767 files across 120 folders under
  /// a real root folder, at 1.05 revisions per entity.
  ///
  /// Arweave ids and uuids are the incompressible part of this payload, and
  /// they dominate it: three transaction ids and two uuids per file. Synthetic
  /// ids built by interpolating a counter gzip almost perfectly and would
  /// flatter the result by several times over, so these are drawn from a
  /// seeded PRNG at the real entropy - 32 bytes for a transaction id, 16 for a
  /// uuid.
  ///
  /// The generator is seeded here rather than in [main] so that both tests
  /// build byte-identical fixtures whatever order they run in. The root
  /// folder's own rows are drawn last for the same reason: appending them
  /// leaves every other row's ids exactly where they were when §1.1 was
  /// measured.
  ///
  /// What comes back is what the rest of the pipeline cannot know for itself:
  /// the folder ids, and a file that was revised after it was created together
  /// with the transaction its *newest* revision points at. Those last two are
  /// the only assertion at this scale that can tell "the file list rendered
  /// 41,767 rows" apart from "the file list rendered 41,767 rows resolved
  /// through the wrong revision".
  Future<
      ({
        List<String> folderIds,
        String revisedFileId,
        String revisedFileLatestMetadataTxId,
        int filesInFirstFolder,
      })> seedMeasuredDrive(
    Database db, {
    required String ownerAddress,
  }) async {
    final rng = Random(20260819);
    const b64 =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    String txId() => List.generate(43, (_) => b64[rng.nextInt(64)]).join();
    String uuid() {
      String hex(int n) =>
          List.generate(n, (_) => '0123456789abcdef'[rng.nextInt(16)]).join();
      return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
    }

    final created = DateTime(2024, 3, 1, 12);
    final folderIds = <String>[];

    var revisedFileId = '';
    var revisedFileLatestMetadataTxId = '';
    var filesInFirstFolder = 0;

    await db.batch((b) {
      b.insert(
        db.drives,
        DrivesCompanion.insert(
          id: driveId,
          rootFolderId: rootFolderId,
          ownerAddress: ownerAddress,
          name: driveName,
          privacy: DrivePrivacyTag.private,
          lastBlockHeight: const Value(watermark),
        ),
      );
      b.insert(
        db.driveRevisions,
        DriveRevisionsCompanion.insert(
          driveId: driveId,
          rootFolderId: rootFolderId,
          name: driveName,
          privacy: DrivePrivacyTag.private,
          metadataTxId: txId(),
          ownerAddress: ownerAddress,
          dateCreated: Value(created),
          action: RevisionAction.create,
        ),
      );

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
        final parentIndex = i % folderCount;
        final parent = folderIds[parentIndex];
        final name = '${nouns[rng.nextInt(nouns.length)]}-'
            '${nouns[rng.nextInt(nouns.length)]}-$i'
            '${exts[rng.nextInt(exts.length)]}';
        final dataTx = txId();

        if (parentIndex == 0) filesInFirstFolder++;

        b.insert(
          db.fileEntries,
          FileEntriesCompanion.insert(
            id: id,
            driveId: driveId,
            parentFolderId: parent,
            name: name,
            path: '/Some Folder Name $parentIndex/$name',
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
          final metadataTxId = txId();

          // The first file to carry a second revision, kept so the render
          // check can prove the file list resolved the newest one.
          if (revisions == 2 && r == 1 && revisedFileId.isEmpty) {
            revisedFileId = id;
            revisedFileLatestMetadataTxId = metadataTxId;
          }

          b.insert(
            db.fileRevisions,
            FileRevisionsCompanion.insert(
              fileId: id,
              driveId: driveId,
              parentFolderId: parent,
              name: name,
              size: 2400000 + i,
              lastModifiedDate: created,
              metadataTxId: metadataTxId,
              dataTxId: dataTx,
              dateCreated: Value(created.add(Duration(minutes: r))),
              dataContentType: const Value('image/jpeg'),
              action: RevisionAction.create,
            ),
          );
        }
      }

      // The root folder, written last so that nothing above it moved. A real
      // drive always has one: a `folder_entries` row for the explorer to open,
      // and the `folder_revisions` row that both the export's chain-origin
      // filter and the importer's root-resolves guard require.
      b.insert(
        db.folderEntries,
        FolderEntriesCompanion.insert(
          id: rootFolderId,
          driveId: driveId,
          name: driveName,
          path: '',
          lastUpdated: Value(created),
          dateCreated: Value(created),
        ),
      );
      b.insert(
        db.folderRevisions,
        FolderRevisionsCompanion.insert(
          folderId: rootFolderId,
          driveId: driveId,
          name: driveName,
          metadataTxId: txId(),
          dateCreated: Value(created),
          action: RevisionAction.create,
        ),
      );
    });

    return (
      folderIds: folderIds,
      revisedFileId: revisedFileId,
      revisedFileLatestMetadataTxId: revisedFileLatestMetadataTxId,
      filesInFirstFolder: filesInFirstFolder,
    );
  }

  /// Resident set size of the whole `flutter_tester` process, in MiB.
  ///
  /// A VM RSS figure and nothing more, and four things have to be said about
  /// it before any of the numbers below mean anything:
  ///
  ///  * It is **not a browser heap**, which is the platform the conclusion is
  ///    actually about. It is not even the Dart heap — it is what the OS has
  ///    resident for the process.
  ///  * It counts the two in-memory SQLite databases this test holds. A real
  ///    producer's database is not in its heap; the fixture's is. The
  ///    `before seeding` sample is there so that cost can be subtracted.
  ///  * `currentRss` falls as well as rises, because the VM returns pages, so
  ///    a sample is what was resident at that instant and not what the stage
  ///    before it reached.
  ///  * [ProcessInfo.maxRss] is **process-wide and monotonic for the whole
  ///    run**. Both tests in this file share one `flutter_tester`, so a run of
  ///    the file reports a peak that includes whatever the weighing test
  ///    allocated first. Run this test alone for a figure that is only about
  ///    this pipeline: `--run-skipped --tags=measurement --name=carries`.
  ///
  /// Both are printed at every stage boundary for the same reason: because
  /// `maxRss` only ever climbs, a stage that leaves it higher than it found it
  /// is a stage that set a new peak, and one that leaves it alone did not.
  /// That is the closest thing to per-stage attribution available without a
  /// sampling thread, and it is why the transient inside a stage — the copy
  /// `ArDriveCrypto.encrypt` makes, say — shows up here and nowhere else.
  ///
  /// It is reported anyway, because the alternative was to estimate, and a
  /// measurement whose limits are stated beats a number nobody took.
  String rss() => '${(ProcessInfo.currentRss / mib).toStringAsFixed(0)} MiB'
      ' (peak so far ${(ProcessInfo.maxRss / mib).toStringAsFixed(0)})';

  test('weighs a 42k-file drive through the real export', () async {
    final db = getTestDb();
    addTearDown(db.close);

    await seedMeasuredDrive(db, ownerAddress: placeholderOwner);

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

  /// The half of the pipeline nothing else runs above ten rows.
  ///
  /// `seal` refuses on the **uncompressed** size against the 100 MiB AES-GCM
  /// boundary, so a 52 MiB payload is permitted — and a permitted payload has
  /// to work. Import has the same gap from the other end: it lands the whole
  /// drive in one drift batch inside one transaction, and nothing had watched
  /// it do that with 41,767 files in front of it.
  ///
  /// So this runs the producer's path and the consumer's path against each
  /// other at full scale, and finishes by asking the question the user asks —
  /// `DriveDao.watchFolderContents`, the query `DriveDetailCubit` listens to,
  /// which is what paints the file list.
  test('carries a 42k-file drive through seal, import and the file list',
      () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    final rssStart = rss();
    final codec = DriveStateEnvelopeCodec();
    final owner = await Wallet.generate();
    final ownerAddress = await owner.getAddress();
    final driveKey = await AesGcm.with256bits().newSecretKey();
    final privateDrive = DriveStateProtection.forDrive(
      privacy: DrivePrivacyTag.private,
      driveKey: driveKey,
    ).protection!;

    // Two databases on purpose: that is the whole point of an artifact.
    final producerDb = getTestDb();
    addTearDown(producerDb.close);
    final consumerDb = getTestDb();
    addTearDown(consumerDb.close);

    final seeded = await seedMeasuredDrive(
      producerDb,
      ownerAddress: ownerAddress,
    );

    // The consumer, as a client that has attached the drive but not synced it:
    // a drive row with its key material and nothing else.
    await consumerDb.into(consumerDb.drives).insert(
          DrivesCompanion.insert(
            id: driveId,
            rootFolderId: rootFolderId,
            ownerAddress: ownerAddress,
            name: driveName,
            privacy: DrivePrivacyTag.private,
            encryptedKey: Value(Uint8List.fromList([1, 2, 3, 4])),
            keyEncryptionIv: Value(Uint8List.fromList([5, 6, 7])),
            driveKeyGenerated: const Value(true),
            lastBlockHeight: const Value(0),
            lastUpdated: Value(DateTime(2020)),
          ),
        );

    final rssSeeded = rss();

    // --- the producer ---------------------------------------------------

    final exportWatch = Stopwatch()..start();
    final export = await exportDriveState(producerDb.driveDao, driveId);
    exportWatch.stop();
    final rssExported = rss();

    final encodeWatch = Stopwatch()..start();
    final plaintext = Uint8List.fromList(
      utf8.encode(jsonEncode(export.toJson())),
    );
    encodeWatch.stop();
    final rssEncoded = rss();

    // Measured on its own so the seal figure below can be attributed: `seal`
    // gzips the same bytes internally, and this is that cost in isolation.
    final gzipWatch = Stopwatch()..start();
    final compressed = GZipEncoder().encode(plaintext)!;
    gzipWatch.stop();

    final sealWatch = Stopwatch()..start();
    final sealed = await codec.seal(
      plaintext: plaintext,
      protection: privateDrive,
      wallet: owner,
    );
    sealWatch.stop();
    final rssSealed = rss();

    expect(sealed.isSealed, isTrue, reason: sealed.toString());
    final envelope = sealed.envelope!;

    // A GCM ciphertext is the length of its plaintext and this codec appends
    // the 16 byte MAC, so the signed data item's size follows from the body
    // exactly — no need to weigh something the codec keeps to itself.
    const macBytes = 16;
    final signedItemBytes = envelope.body.lengthInBytes - macBytes;

    // Printed here rather than gathered into one report at the end, and the
    // same for each block below. A stage of this pipeline falling over at
    // scale is the most useful thing this test can find out, and a report
    // assembled after the last stage is a report that a failure in the last
    // stage takes down with it.
    //
    // ignore: avoid_print
    print('''

=== MEASURED, seal at real scale ===
uncompressed JSON         ${plaintext.lengthInBytes} bytes = ${(plaintext.lengthInBytes / mib).toStringAsFixed(2)} MiB
gzipped (standalone)      ${compressed.length} bytes = ${(compressed.length / mib).toStringAsFixed(2)} MiB
signed ANS-104 data item  $signedItemBytes bytes = ${(signedItemBytes / mib).toStringAsFixed(2)} MiB
sealed body (ct + MAC)    ${envelope.body.lengthInBytes} bytes = ${(envelope.body.lengthInBytes / mib).toStringAsFixed(2)} MiB

AES-GCM holds             ${(signedItemBytes / mib).toStringAsFixed(2)} MiB - the compressed, signed item
D5 refuses above          ${(maxSizeSupportedByGCMEncryption / mib).toStringAsFixed(0)} MiB - of the uncompressed payload

export                    ${exportWatch.elapsedMilliseconds} ms
jsonEncode + utf8         ${encodeWatch.elapsedMilliseconds} ms
gzip alone                ${gzipWatch.elapsedMilliseconds} ms
seal (gzip+sign+GCM)      ${sealWatch.elapsedMilliseconds} ms
  of which not gzip       ${sealWatch.elapsedMilliseconds - gzipWatch.elapsedMilliseconds} ms
=== END ===
''');

    // --- the consumer ---------------------------------------------------

    final candidate = DriveStateArtifactCandidate(
      txId: 'measured-artifact-tx-id',
      ownerAddress: ownerAddress,
      tags: {
        EntityTag.arFs: '0.15',
        EntityTag.entityType: EntityTypeTag.driveState,
        EntityTag.driveId: driveId,
        EntityTag.driveStateId: 'measured-drive-state-id',
        EntityTag.stateVersion: currentVersionString,
        EntityTag.contentType: ContentType.octetStream,
        EntityTag.blockStart: '${export.coverage.blockStart}',
        EntityTag.blockEnd: '${export.coverage.blockEnd}',
        EntityTag.entityCount: '${export.entityCount}',
        EntityTag.cipher: Cipher.aes256,
        EntityTag.cipherIv: envelope.cipherIvAsBase64!,
      },
      minedAtHeight: export.coverage.blockEnd,
    );

    final importer = DriveStateImporter(consumerDb.driveDao, codec: codec);

    final importWatch = Stopwatch()..start();
    final result = await importer.import(
      candidate: candidate,
      body: envelope.body,
      protection: privateDrive,
      expectedOwnerAddress: ownerAddress,
    );
    importWatch.stop();
    final rssImported = rss();

    expect(result.outcome, DriveStateOutcome.used, reason: result.detail);
    final stats = result.stats!;

    // ignore: avoid_print
    print('''

=== MEASURED, import at real scale ===
outcome                   ${result.outcome.code}
entities imported         ${stats.entitiesImported} (folders=${stats.foldersWritten} files=${stats.filesWritten})
folders materialised      ${stats.foldersMaterialised}
revisions written         ${stats.revisionsWritten}
network_transactions      ${stats.transactionsWritten}
rows kept locally newer   ${stats.rowsKeptLocallyNewer}
watermark                 ${stats.watermark}

open+decompress+parse     ${stats.parseDuration.inMilliseconds} ms
merge (one db txn)        ${stats.mergeDuration.inMilliseconds} ms
import, end to end        ${importWatch.elapsedMilliseconds} ms
=== END ===
''');

    // --- the file list --------------------------------------------------

    final rootWatch = Stopwatch()..start();
    final root = await consumerDb.driveDao
        .watchFolderContents(driveId, folderId: rootFolderId)
        .first;
    rootWatch.stop();

    final oneFolderWatch = Stopwatch()..start();
    final firstFolder = await consumerDb.driveDao
        .watchFolderContents(driveId, folderId: seeded.folderIds.first)
        .first;
    oneFolderWatch.stop();

    // Every folder, because "the drive opens" is not the same claim as "every
    // file in it came back". The two INNER JOINs onto `network_transactions`
    // drop a file silently and per folder, so only a full sweep counts them.
    final allFoldersWatch = Stopwatch()..start();
    var renderedFiles = 0;
    for (final folderId in seeded.folderIds) {
      final contents = await consumerDb.driveDao
          .watchFolderContents(driveId, folderId: folderId)
          .first;
      renderedFiles += contents.files.length;
    }
    allFoldersWatch.stop();
    final rssRendered = rss();

    // --- the same artifact again ----------------------------------------
    //
    // Not a corner case: it is what the next sync does. An artifact is only
    // refused for coverage when its `Block-End` is *below* the drive's
    // watermark, and after the import above the two are equal — deliberately,
    // so that a range a sync skipped can still be filled. The artifact is
    // immutable and discovery orders it newest-first, so until the drive syncs
    // past `Block-End` every sync fetches it and runs this again.
    //
    // Every write is an `insertOrIgnore` onto rows that are already there, so
    // nothing changes. The statements still run, and this is what they cost.
    final reimportWatch = Stopwatch()..start();
    final reimport = await importer.import(
      candidate: candidate,
      body: envelope.body,
      protection: privateDrive,
      expectedOwnerAddress: ownerAddress,
    );
    reimportWatch.stop();
    final rssReimported = rss();

    expect(reimport.outcome, DriveStateOutcome.used, reason: reimport.detail);
    final reimportStats = reimport.stats!;

    // ignore: avoid_print
    print('''

=== MEASURED, the file list on the restored drive ===
root folder               ${root.subfolders.length} subfolders, ${root.files.length} files, ${rootWatch.elapsedMilliseconds} ms
one folder                ${firstFolder.files.length} files, ${oneFolderWatch.elapsedMilliseconds} ms
every folder              $renderedFiles files over ${seeded.folderIds.length} folders, ${allFoldersWatch.elapsedMilliseconds} ms
files that came back      $renderedFiles of $fileCount
=== END ===

=== MEASURED, the same artifact imported a second time ===
outcome                   ${reimport.outcome.code}
entities offered          ${reimportStats.entitiesImported} (folders=${reimportStats.foldersWritten} files=${reimportStats.filesWritten})
revisions actually added  ${reimportStats.revisionsWritten}
transactions added        ${reimportStats.transactionsWritten}
rows kept locally newer   ${reimportStats.rowsKeptLocallyNewer}

open+decompress+parse     ${reimportStats.parseDuration.inMilliseconds} ms
merge (one db txn)        ${reimportStats.mergeDuration.inMilliseconds} ms
re-import, end to end     ${reimportWatch.elapsedMilliseconds} ms
  first import was        ${importWatch.elapsedMilliseconds} ms
=== END ===

=== MEASURED, process RSS - a VM figure, not a browser heap ===
before seeding            $rssStart
after seeding             $rssSeeded   <- the fixture's own database is in this
after export              $rssExported
after jsonEncode + utf8   $rssEncoded
after seal                $rssSealed
after import              $rssImported
after rendering           $rssRendered
after re-import           $rssReimported
run peak                  ${(ProcessInfo.maxRss / mib).toStringAsFixed(0)} MiB - process-wide, monotonic; see rss()
=== END ===
''');

    // The measurement is the point, but a pipeline that ran and lost the drive
    // would print a table of numbers about nothing. These are what turn the
    // numbers above into claims.
    expect(stats.filesWritten, fileCount);
    expect(stats.foldersWritten, folderCount + 1);
    expect(stats.foldersMaterialised, 0,
        reason: 'a drive whose root and every parent travelled needs no '
            'stand-ins invented for it');
    expect(stats.watermark, watermark);
    expect(root.subfolders, hasLength(folderCount));
    expect(firstFolder.files, hasLength(seeded.filesInFirstFolder));
    expect(renderedFiles, fileCount,
        reason: 'every file the artifact carried must render');

    // `where`, not `firstWhere`: a folder that rendered nothing has to fail as
    // a missing file and not as a StateError out of an iterator, or the run
    // that finds the interesting bug reports the wrong thing.
    final revised =
        firstFolder.files.where((f) => f.id == seeded.revisedFileId);
    expect(revised, hasLength(1),
        reason: 'the revised file must be one of the rendered rows');
    expect(revised.single.metadataTx.id, seeded.revisedFileLatestMetadataTxId,
        reason: 'the file list must resolve a file through its newest '
            'revision, not its first');
    expect(revised.single.metadataTx.status, TransactionStatus.confirmed,
        reason: 'a restored drive must not show every file as pending');

    // The second import must change nothing. If it ever adds a row, the merge
    // is not idempotent and this drive gains duplicates on every sync.
    expect(reimportStats.revisionsWritten, 0);
    expect(reimportStats.transactionsWritten, 0);
    expect(reimportStats.licensesWritten, 0);
    expect(reimportStats.watermark, watermark);
  }, timeout: const Timeout(Duration(minutes: 30)));
}
