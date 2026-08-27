import 'package:ardrive/drive_state/data/drive_state_export.dart';
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
import 'package:ardrive/drive_state/domain/drive_state_format_version.dart';
import 'package:ardrive/drive_state/domain/drive_state_protection.dart';
import 'package:ardrive/drive_state/domain/drive_state_sync_skip_status.dart';
import 'package:ardrive/drive_state_sqlite/artifact_sink.dart';
import 'package:ardrive/drive_state_sqlite/artifact_to_export.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:test/test.dart';

import '../../test_utils/utils.dart';
import '../artifact_sql.dart';

/// The rows a sealed payload actually carries, read the way the importer
/// reads them: the artifact is attached as a database and its tables are
/// selected from, never parsed.
Future<DriveStateExport> rowsSealedIn(Uint8List payload) async {
  final scratch = getTestDb();
  final source = await createArtifactSource('creation-service', payload);
  try {
    await scratch.customStatement(
      'ATTACH DATABASE ? AS artifact',
      [source.path],
    );
    try {
      return await readArtifactAsExport(scratch, alias: 'artifact');
    } finally {
      await scratch.customStatement('DETACH DATABASE artifact');
    }
  } finally {
    await source.dispose();
    await scratch.close();
  }
}

/// The same rows, ordered the way [exportDriveState] orders them.
///
/// An artifact carries its rows in the order they were copied, which is the
/// producer's insertion order, and `DriveStateExport` compares its lists
/// element by element. Ordering both sides is what lets the comparison be
/// about the rows rather than about a scan order neither side promises.
DriveStateExport inTheOrderTheExportUses(DriveStateExport export) =>
    DriveStateExport(
      drive: export.drive,
      folders: [...export.folders]..sort((a, b) => a.id.compareTo(b.id)),
      files: [...export.files]..sort((a, b) => a.id.compareTo(b.id)),
      driveRevisions: [...export.driveRevisions]
        ..sort((a, b) => a.dateCreated.compareTo(b.dateCreated)),
      folderRevisions: [...export.folderRevisions]..sort((a, b) =>
          a.folderId != b.folderId
              ? a.folderId.compareTo(b.folderId)
              : a.dateCreated.compareTo(b.dateCreated)),
      fileRevisions: [...export.fileRevisions]..sort((a, b) =>
          a.fileId != b.fileId
              ? a.fileId.compareTo(b.fileId)
              : a.dateCreated.compareTo(b.dateCreated)),
      licenses: [...export.licenses]
        ..sort((a, b) => a.licenseTxId.compareTo(b.licenseTxId)),
      coverage: export.coverage,
      version: export.version,
    );

/// The creation path, and above all the one thing it must refuse.
///
/// `docs/drive-state/DECISIONS.md` D3 exists because an artifact is permanent:
/// a drive published from a sync that skipped entities records that gap on
/// Arweave forever, and every importer afterwards adopts its `Block-End` and
/// skips the range the gap is in. So the interesting assertions here are not
/// that a good drive produces a good artifact — they are that a drive which
/// might have a hole produces nothing at all, and that nothing was sealed on
/// the way to saying so.
void main() {
  const driveId = 'drive-id';
  const rootFolderId = 'root-folder-id';
  const nestedFolderId = 'nested-folder-id';
  const emptyFolderCount = 3;
  const rootFileCount = 4;
  const nestedFileCount = 2;

  /// 1 root + 1 nested + 3 empty folders, 6 files, and the drive itself.
  const expectedEntityCount =
      2 + emptyFolderCount + rootFileCount + nestedFileCount + 1;

  const lastBlockHeight = 1814228;

  late Database db;
  late DriveDao driveDao;
  late Wallet wallet;
  late String ownerAddress;
  late SecretKey driveKey;

  setUpAll(() async {
    // Reading a sealed payload back opens a scratch database beside the
    // fixture's own, which is what drift warns about and is not a race here.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    // The fixed test JWK rather than a generated wallet: this suite signs
    // once, and key generation would dominate its runtime.
    wallet = getTestWallet();
    ownerAddress = await wallet.getAddress();
    driveKey = SecretKey(List.filled(32, 7));
  });

  setUp(() async {
    db = getTestDb();
    driveDao = db.driveDao;

    await addTestFilesToDb(
      db,
      driveId: driveId,
      rootFolderId: rootFolderId,
      nestedFolderId: nestedFolderId,
      emptyNestedFolderCount: emptyFolderCount,
      emptyNestedFolderIdPrefix: 'empty-nested-folder-id',
      rootFolderFileCount: rootFileCount,
      nestedFolderFileCount: nestedFileCount,
    );
    // `addTestFilesToDb` writes file revisions but no folder ones, and the
    // export carries only chain-derived rows. This is a drive whose folders
    // all synced.
    await addFolderRevisionsToDb(
      db,
      driveId: driveId,
      folderIds: [
        rootFolderId,
        nestedFolderId,
        ...List.generate(emptyFolderCount, (i) => 'empty-nested-folder-id$i'),
      ],
    );

    // A private drive this wallet owns, synced to a real height: the only
    // shape the service will produce anything for.
    await (db.update(db.drives)..where((d) => d.id.equals(driveId))).write(
      DrivesCompanion(
        privacy: const Value(DrivePrivacyTag.private),
        ownerAddress: Value(ownerAddress),
        lastBlockHeight: const Value(lastBlockHeight),
      ),
    );
  });

  tearDown(() => db.close());

  DriveStateCreationService serviceWith({
    required DriveStateSyncSkipStatus skipStatus,
    DriveStateEnvelopeCodec? codec,
  }) =>
      DriveStateCreationService(
        driveDao: driveDao,
        skipSource: _FixedSkipSource(skipStatus),
        codec: codec,
        newArtifactId: () => 'artifact-id',
      );

  /// The tags as a client reading them back off GraphQL would see them.
  Map<String, String> tagsOf(TransactionBase tx) => {
        for (final tag in tx.tags)
          decodeBase64ToString(tag.name): decodeBase64ToString(tag.value),
      };

  group('the D3 precondition', () {
    test('refuses a drive whose last sync skipped entities', () async {
      final codec = _RecordingCodec();
      final service = serviceWith(
        skipStatus: const DriveStateSyncSkipStatus.skipped(
          skippedEntityCount: 3,
          reason: 'The last sync of this drive could not read 3 items.',
        ),
        codec: codec,
      );

      final result = await service.prepare(
        driveId: driveId,
        driveKey: driveKey,
        wallet: wallet,
      );

      expect(result.isRefused, isTrue);
      expect(result.isPrepared, isFalse);
      expect(result.artifact, isNull);
      expect(
        result.refusal,
        DriveStateCreationRefusal.syncSkippedEntities,
        reason: 'a drive with a known gap must be refused for that reason, '
            'not for some incidental one',
      );
      expect(result.reason, contains('3 items'));

      // Nothing was sealed on the way to refusing. The refusal is not a
      // discarded artifact — no payload was ever built, so there is nothing
      // for a later change to accidentally hand to an uploader.
      expect(codec.sealCalls, 0);
    });

    test('refuses when the skip state cannot be established', () async {
      final codec = _RecordingCodec();
      final service = serviceWith(
        skipStatus: const DriveStateSyncSkipStatus.unknown(
          'No sync has finished yet.',
        ),
        codec: codec,
      );

      final result = await service.prepare(
        driveId: driveId,
        driveKey: driveKey,
        wallet: wallet,
      );

      expect(result.refusal, DriveStateCreationRefusal.skipStateUnknown);
      expect(result.artifact, isNull);
      expect(codec.sealCalls, 0);
    });

    test('a clean sync is the only status that gets past the check', () async {
      final codec = _RecordingCodec();
      final service = serviceWith(
        skipStatus: const DriveStateSyncSkipStatus.clean(),
        codec: codec,
      );

      final result = await service.prepare(
        driveId: driveId,
        driveKey: driveKey,
        wallet: wallet,
      );

      expect(result.isPrepared, isTrue);
      expect(codec.sealCalls, 1);
    });
  });

  group('the prepared artifact', () {
    late DriveStateCreationResult result;
    late PreparedDriveStateArtifact artifact;
    late _RecordingCodec codec;

    setUp(() async {
      codec = _RecordingCodec();
      result = await serviceWith(
        skipStatus: const DriveStateSyncSkipStatus.clean(),
        codec: codec,
      ).prepare(
        driveId: driveId,
        driveKey: driveKey,
        wallet: wallet,
      );

      expect(result.isPrepared, isTrue, reason: result.reason);
      artifact = result.artifact!;
    });

    test('declares the entity count the export actually carries', () async {
      final export = await exportDriveState(driveDao, driveId);

      expect(export.entityCount, expectedEntityCount);
      expect(artifact.entityCount, expectedEntityCount);

      final tx = Transaction();
      artifact.entity.addEntityTagsToTransaction(tx);

      expect(tagsOf(tx)[EntityTag.entityCount], '$expectedEntityCount');
    });

    /// The importer refuses any artifact whose tags disagree with the
    /// coverage claim inside the signed payload, so an artifact that fails
    /// this check is one nobody can ever use - paid for, on chain, permanent.
    ///
    /// It is worth a test even though [DriveStateEntity.fromEnvelope] now
    /// takes the claim itself and cannot be passed anything else: this is the
    /// assertion that survives someone deciding the constructor would be
    /// tidier with two integers.
    test('tags the block range the sealed payload itself claims', () async {
      final claimed = codec.lastPayloadMeta!;

      final tx = Transaction();
      artifact.entity.addEntityTagsToTransaction(tx);
      final tags = tagsOf(tx);

      expect(tags[EntityTag.blockStart], '${claimed['blockStart']}');
      expect(tags[EntityTag.blockEnd], '${claimed['blockEnd']}');
      expect(claimed['blockEnd'], lastBlockHeight);
    });

    /// The version has exactly the shape the coverage claim has: it is written
    /// twice, once in a tag anybody can rewrite and once inside the signature,
    /// and an importer refuses an artifact whose two copies disagree. A
    /// producer that let them drift would publish something no reader accepts,
    /// permanently and having paid for it - so the assertion is that they come
    /// from one constant, not two that happen to match today.
    test('tags the same format version the sealed payload declares', () {
      final declared = codec.lastPayloadMeta!['version'];

      final tx = Transaction();
      artifact.entity.addEntityTagsToTransaction(tx);

      expect(tagsOf(tx)[EntityTag.stateVersion], declared);
      expect(declared, DriveStateFormatVersion.current.toString());
    });

    test("declares Block-End as the drive's own sync watermark", () {
      expect(artifact.blockEnd, lastBlockHeight);

      final tx = Transaction();
      artifact.entity.addEntityTagsToTransaction(tx);

      expect(tagsOf(tx)[EntityTag.blockEnd], '$lastBlockHeight');
    });

    test('publishes a full copy: Block-Start is 0', () {
      expect(artifact.blockStart, 0);

      final tx = Transaction();
      artifact.entity.addEntityTagsToTransaction(tx);

      expect(tagsOf(tx)[EntityTag.blockStart], '0');
    });

    test('claims data across the range it covers, because it carries rows', () {
      expect(artifact.dataStart, 0);
      expect(artifact.dataEnd, lastBlockHeight);
    });

    test('carries the sealed body and its cipher tags', () {
      expect(artifact.entity.data, isNotNull);
      expect(artifact.sizeInBytes, artifact.entity.data!.lengthInBytes);
      expect(artifact.entity.cipher, 'AES256-GCM');
      expect(artifact.entity.cipherIv, isNotNull);
    });

    test('is unsent: nothing has given it a transaction id', () {
      // `txId` is late-initialised, so an entity that has never been through
      // an upload throws on the read. That throw is the assertion: the service
      // prepares an artifact and sending it is the user's action, so nothing
      // on this path may have taken it.
      expect(
        () => artifact.entity.txId,
        throwsA(
          predicate<Object>(
            (e) => e is Error && e.toString().contains('txId'),
            'an uninitialised txId',
          ),
        ),
      );
    });

    test('names the drive so the confirmation can show what it would publish',
        () {
      expect(artifact.driveId, driveId);
      expect(artifact.driveName, 'fake-drive-name');
    });

    test('seals a payload that round-trips back to the exported rows',
        () async {
      expect(
        inTheOrderTheExportUses(await rowsSealedIn(codec.lastPlaintext!)),
        equals(inTheOrderTheExportUses(
          await exportDriveState(driveDao, driveId),
        )),
      );
    });

    test('asked the codec for the encrypted chain, carrying the drive key', () {
      expect(codec.lastProtection, isA<DriveStateEncrypted>());
      expect(
        (codec.lastProtection! as DriveStateEncrypted).driveKey,
        same(driveKey),
      );
    });
  });

  /// A public drive, which used to be refused outright.
  ///
  /// The assertions that matter are the two differences and the long list of
  /// things that are *not* different: the tags, the coverage, the entity
  /// count, the payload and every remaining gate are the private drive's.
  group('a public drive', () {
    late PreparedDriveStateArtifact artifact;
    late _RecordingCodec codec;

    setUp(() async {
      await (db.update(db.drives)..where((d) => d.id.equals(driveId))).write(
        const DrivesCompanion(privacy: Value(DrivePrivacyTag.public)),
      );

      codec = _RecordingCodec();
      final result = await serviceWith(
        skipStatus: const DriveStateSyncSkipStatus.clean(),
        codec: codec,
      ).prepare(
        // A public drive has no `encryptedKey`, so `DriveDao.getDriveKey`
        // hands the caller null and this is what the service is given.
        driveId: driveId,
        driveKey: null,
        wallet: wallet,
      );

      expect(result.isPrepared, isTrue, reason: result.reason);
      artifact = result.artifact!;
    });

    test('prepares an artifact rather than refusing', () {
      expect(artifact.entityCount, expectedEntityCount);
      expect(artifact.driveId, driveId);
      expect(artifact.sizeInBytes, greaterThan(0));
    });

    test('asked the codec for the unencrypted chain', () {
      expect(codec.lastProtection, isA<DriveStateUnencrypted>());
      expect(codec.lastProtection!.isEncrypted, isFalse);
    });

    test('carries no cipher tags at all, and neither half of them', () {
      expect(artifact.isEncrypted, isFalse);
      expect(artifact.entity.cipher, isNull);
      expect(artifact.entity.cipherIv, isNull);

      final tx = Transaction();
      artifact.entity.addEntityTagsToTransaction(tx);
      final tags = tagsOf(tx);

      // Absent, not empty and not `none`: their absence is the discriminator,
      // so a third state would be one nobody specified.
      expect(tags.containsKey(EntityTag.cipher), isFalse);
      expect(tags.containsKey(EntityTag.cipherIv), isFalse);
    });

    test('tags everything else exactly as a private drive does', () {
      final tx = Transaction();
      artifact.entity.addEntityTagsToTransaction(tx);
      final tags = tagsOf(tx);

      expect(tags[EntityTag.entityType], EntityTypeTag.driveState);
      expect(tags[EntityTag.driveId], driveId);
      expect(tags[EntityTag.blockStart], '0');
      expect(tags[EntityTag.blockEnd], '$lastBlockHeight');
      expect(tags[EntityTag.entityCount], '$expectedEntityCount');
      // Still this build's version: public support is folded into the
      // initial format rather than added as a minor bump, because nothing has
      // been published.
      expect(
        tags[EntityTag.stateVersion],
        DriveStateFormatVersion.current.toString(),
      );
    });

    test('seals the same payload a private drive would', () async {
      expect(
        inTheOrderTheExportUses(await rowsSealedIn(codec.lastPlaintext!)),
        equals(inTheOrderTheExportUses(
          await exportDriveState(driveDao, driveId),
        )),
      );
      expect(
        codec.lastPayloadMeta!['version'],
        DriveStateFormatVersion.current.toString(),
      );
    });

    test('is unsent, like every other prepared artifact', () {
      expect(
        () => artifact.entity.txId,
        throwsA(
          predicate<Object>(
            (e) => e is Error && e.toString().contains('txId'),
            'an uninitialised txId',
          ),
        ),
      );
    });

    group('every other gate still applies', () {
      Future<DriveStateCreationResult> preparePublic({
        DriveStateSyncSkipStatus skipStatus =
            const DriveStateSyncSkipStatus.clean(),
      }) =>
          serviceWith(skipStatus: skipStatus).prepare(
            driveId: driveId,
            driveKey: null,
            wallet: wallet,
          );

      test('a sync that skipped entities still refuses', () async {
        final result = await preparePublic(
          skipStatus: const DriveStateSyncSkipStatus.skipped(
            skippedEntityCount: 3,
            reason: 'The last sync of this drive could not read 3 items.',
          ),
        );

        expect(
          result.refusal,
          DriveStateCreationRefusal.syncSkippedEntities,
        );
      });

      test('an unknown skip state still refuses', () async {
        final result = await preparePublic(
          skipStatus: const DriveStateSyncSkipStatus.unknown(
            'This drive has not been synced by this session.',
          ),
        );

        expect(result.refusal, DriveStateCreationRefusal.skipStateUnknown);
      });

      test('a wallet that does not own the drive still refuses', () async {
        await (db.update(db.drives)..where((d) => d.id.equals(driveId))).write(
          const DrivesCompanion(ownerAddress: Value('somebody-else')),
        );

        expect(
          (await preparePublic()).refusal,
          DriveStateCreationRefusal.notDriveOwner,
        );
      });

      test('no sync watermark still refuses', () async {
        await (db.update(db.drives)..where((d) => d.id.equals(driveId))).write(
          const DrivesCompanion(lastBlockHeight: Value(0)),
        );

        expect(
          (await preparePublic()).refusal,
          DriveStateCreationRefusal.noWatermark,
        );
      });
    });
  });

  group('what else it refuses', () {
    Future<DriveStateCreationResult> prepare({String id = driveId}) =>
        serviceWith(skipStatus: const DriveStateSyncSkipStatus.clean()).prepare(
          driveId: id,
          driveKey: driveKey,
          wallet: wallet,
        );

    test('a drive that is not in the database', () async {
      final result = await prepare(id: 'no-such-drive');

      expect(result.refusal, DriveStateCreationRefusal.driveNotFound);
    });

    test('a private drive whose key is not available', () async {
      // The refusal that replaced the public-drive one, and the reason the
      // two had to stop looking the same: both arrive here as a null key,
      // and only one of them is a reason not to publish.
      final result =
          await serviceWith(skipStatus: const DriveStateSyncSkipStatus.clean())
              .prepare(driveId: driveId, driveKey: null, wallet: wallet);

      expect(
        result.refusal,
        DriveStateCreationRefusal.protectionUnavailable,
      );
      expect(result.artifact, isNull);
      expect(result.reason, contains('private'));
    });

    test('a drive whose privacy column is neither public nor private',
        () async {
      await (db.update(db.drives)..where((d) => d.id.equals(driveId))).write(
        const DrivesCompanion(privacy: Value('something-else')),
      );

      final result = await prepare();

      expect(
        result.refusal,
        DriveStateCreationRefusal.protectionUnavailable,
      );
      // Refused rather than defaulted to the clear, which is the mistake the
      // absence of a default branch exists to prevent.
      expect(result.artifact, isNull);
    });

    test('a public drive it was handed a drive key for', () async {
      await (db.update(db.drives)..where((d) => d.id.equals(driveId))).write(
        const DrivesCompanion(privacy: Value(DrivePrivacyTag.public)),
      );

      final result = await prepare();

      expect(
        result.refusal,
        DriveStateCreationRefusal.protectionUnavailable,
      );
    });

    test('a drive this wallet does not own', () async {
      await (db.update(db.drives)..where((d) => d.id.equals(driveId))).write(
        const DrivesCompanion(ownerAddress: Value('somebody-else')),
      );

      final result = await prepare();

      expect(result.refusal, DriveStateCreationRefusal.notDriveOwner);
    });

    test('a drive with no sync watermark to publish', () async {
      await (db.update(db.drives)..where((d) => d.id.equals(driveId))).write(
        const DrivesCompanion(lastBlockHeight: Value(0)),
      );

      final result = await prepare();

      expect(result.refusal, DriveStateCreationRefusal.noWatermark);
    });

    test('a payload the codec will not seal', () async {
      final service = serviceWith(
        skipStatus: const DriveStateSyncSkipStatus.clean(),
        codec: _RecordingCodec(
          result: const DriveStateSealResult.refused(
            DriveStateEnvelopeFailure.plaintextTooLarge,
            'too large',
          ),
        ),
      );

      final result = await service.prepare(
        driveId: driveId,
        driveKey: driveKey,
        wallet: wallet,
      );

      expect(result.refusal, DriveStateCreationRefusal.payloadTooLarge);
      expect(result.artifact, isNull);
    });
  });
}

/// A skip source that answers whatever the test set it to.
class _FixedSkipSource implements DriveStateSyncSkipSource {
  final DriveStateSyncSkipStatus _status;

  const _FixedSkipSource(this._status);

  @override
  DriveStateSyncSkipStatus statusFor(String driveId) => _status;
}

/// The real codec's seal, plus a record of whether it was reached and with
/// what.
///
/// Sealing is a real gzip, a real RSA signature and a real AES-GCM
/// encryption — worth doing once for the artifact tests, and worth counting
/// for the refusal ones, where the assertion is that it never happened.
class _RecordingCodec implements DriveStateEnvelopeCodec {
  final DriveStateEnvelopeCodec _real = DriveStateEnvelopeCodec();

  /// When set, returned instead of sealing, so a codec refusal can be
  /// exercised without a payload big enough to cause one.
  final DriveStateSealResult? result;

  _RecordingCodec({this.result});

  int sealCalls = 0;
  Uint8List? lastPlaintext;

  @override
  int get maxPlaintextBytes => _real.maxPlaintextBytes;

  /// The `meta` row of the artifact the service sealed.
  ///
  /// The payload is a SQLite database, so what the artifact claims about
  /// itself is read with a query rather than looked up in a decoded map.
  Map<String, Object?>? get lastPayloadMeta => lastPlaintext == null
      ? null
      : artifactRow(lastPlaintext!, 'SELECT * FROM meta');

  /// What the service resolved from the drive row, recorded so a test can
  /// assert the codec was asked for the chain the drive's privacy calls for -
  /// which is the only place that decision is taken.
  DriveStateProtection? lastProtection;

  @override
  Future<DriveStateSealResult> seal({
    required Uint8List plaintext,
    required DriveStateProtection protection,
    required Wallet wallet,
  }) async {
    sealCalls++;
    lastPlaintext = plaintext;
    lastProtection = protection;

    return result ??
        await _real.seal(
          plaintext: plaintext,
          protection: protection,
          wallet: wallet,
        );
  }

  @override
  Future<DriveStateOpenResult> open({
    required DriveStateEnvelope envelope,
    required DriveStateProtection protection,
    required String expectedOwnerAddress,
  }) =>
      throw UnimplementedError('the creation path never opens an artifact');
}
