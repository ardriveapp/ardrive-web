import 'dart:convert';

import 'package:ardrive/drive_state/data/drive_state_export.dart';
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
import 'package:ardrive/drive_state/domain/drive_state_sync_skip_status.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:test/test.dart';

import '../../test_utils/utils.dart';

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

    test('claims data across the range it covers, because it carries rows',
        () {
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
      final export = await exportDriveState(driveDao, driveId);

      expect(
        DriveStateExport.fromJson(codec.lastPayloadJson!),
        equals(export),
      );
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

    test('a public drive', () async {
      await (db.update(db.drives)..where((d) => d.id.equals(driveId))).write(
        const DrivesCompanion(privacy: Value(DrivePrivacyTag.public)),
      );

      final result = await prepare();

      expect(result.refusal, DriveStateCreationRefusal.publicDriveUnsupported);
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

  Map<String, dynamic>? get lastPayloadJson => lastPlaintext == null
      ? null
      : jsonDecode(utf8.decode(lastPlaintext!)) as Map<String, dynamic>;

  @override
  Future<DriveStateSealResult> seal({
    required Uint8List plaintext,
    required SecretKey driveKey,
    required Wallet wallet,
  }) async {
    sealCalls++;
    lastPlaintext = plaintext;

    return result ??
        await _real.seal(
          plaintext: plaintext,
          driveKey: driveKey,
          wallet: wallet,
        );
  }

  @override
  Future<DriveStateOpenResult> open({
    required DriveStateEnvelope envelope,
    required SecretKey driveKey,
    required String expectedOwnerAddress,
  }) =>
      throw UnimplementedError('the creation path never opens an artifact');
}
