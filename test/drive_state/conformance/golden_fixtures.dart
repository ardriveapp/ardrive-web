/// Golden drive state fixtures: artifacts built by this app's own producer and
/// mutated into every malformed shape a reader must refuse, each recorded with
/// the outcome this app's importer gives it.
///
/// They are the conformance suite for a second reader. ardrive-core-js copies
/// `test/fixtures/drive_state/` and must reach the same outcome on every one,
/// and the same rows on every one this app uses. The format of a fixture is in
/// that directory's README.
///
/// Everything is deterministic except gzip's timestamp, so a regenerated
/// fixture has the same SQLite payload, tags and outcome but not the same
/// sealed bytes. The checked-in body is the one a second reader is tested
/// against.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
import 'package:ardrive/drive_state/domain/drive_state_protection.dart';
import 'package:ardrive/drive_state/domain/drive_state_sync_skip_status.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_schema.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:cryptography/cryptography.dart' hide Cipher;
import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import '../../test_utils/utils.dart';
import '../artifact_sql.dart';

const fixturesPath = 'test/fixtures/drive_state';

/// The drive every fixture is about.
const fixtureDriveId = '6e5f8f5a-2d1b-4c3e-9a7b-0c1d2e3f4a5b';
const fixtureRootFolderId = '0f1e2d3c-4b5a-4968-8776-655443322110';

/// The transaction id every fixture is published under. Never fetched.
const fixtureTxId = 'DriveStateFixtureTransactionId0000000000000';

/// The `Drive-State-Id` and `App-Version` the producer is run with.
const fixtureDriveStateId = '9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d';
const fixtureAppVersion = '2.88.1';

/// `Unix-Time`: 2026-10-20T00:00:00Z.
const fixtureUnixTime = 1792454400;

/// The drive key of the private fixtures. A test key, never a real drive's.
final fixtureDriveKey = Uint8List.fromList(
  List<int>.generate(32, (i) => (i * 37 + 11) % 256),
);

/// The AES-GCM nonce of the private fixtures. Chosen so that its base64url and
/// standard base64 forms differ (`-` and `_` against `+` and `/`), so the
/// fixture that tags it in standard base64 tests something.
final fixtureNonce = Uint8List.fromList(
  [0xfb, 0xef, 0xbe, 0xfb, 0xff, 0xff, 0x01, 0x23, 0x45, 0x67, 0x89, 0xab],
);

/// One fixture: what a reader is handed, and what it should make of it.
class GoldenFixture {
  GoldenFixture({
    required this.name,
    required this.description,
    required this.body,
    required this.tags,
    required this.uploadedBy,
    required this.reader,
    required this.payloadSha256,
    required this.outcome,
    required this.detail,
    required this.tables,
  });

  final String name;
  final String description;

  /// The transaction's data, exactly as a gateway serves it.
  final Uint8List body;

  /// The transaction's tags, in the order the producer wrote them.
  final List<({String name, String value})> tags;

  /// The transaction's owner, as the indexer reports it.
  final String uploadedBy;

  /// What the reader holds before it reads the fixture.
  final FixtureReader reader;

  /// SHA-256 of the SQLite payload inside [body], or null when there is none
  /// to reach.
  final String? payloadSha256;

  /// The `DriveStateOutcome` this app's importer gives the fixture, by name.
  final String outcome;

  /// This app's reason for [outcome], for a person reading the fixture. Not
  /// part of conformance: another reader words its reasons its own way.
  final String? detail;

  /// Every table of the payload, row by row in `rowid` order, when [outcome]
  /// is `used`.
  final Map<String, List<Map<String, Object?>>>? tables;

  Map<String, Object?> toSidecar() => {
        'name': name,
        'description': description,
        'body': '$name.bin',
        'transaction': {
          'id': fixtureTxId,
          'owner': uploadedBy,
          'tags': [
            for (final t in tags) {'name': t.name, 'value': t.value}
          ],
        },
        'reader': reader.toJson(),
        'payloadSha256': payloadSha256,
        'expected': {
          'outcome': outcome,
          'detail': detail,
          if (tables != null) 'tables': tables,
        },
      };
}

/// The state of the client reading a fixture.
class FixtureReader {
  const FixtureReader({
    required this.ownerAddress,
    required this.privacy,
    required this.driveKey,
    this.syncedToBlock = 0,
  });

  /// The drive owner the client knows: who created the drive's first entity.
  final String ownerAddress;

  /// The drive's privacy, from the client's own drive row.
  final String privacy;

  /// The drive key the client holds, or null for a public drive.
  final Uint8List? driveKey;

  /// The height the client has already synced the drive to.
  final int syncedToBlock;

  Map<String, Object?> toJson() => {
        'driveId': fixtureDriveId,
        'ownerAddress': ownerAddress,
        'privacy': privacy,
        'driveKey':
            driveKey == null ? null : utils.encodeBytesToBase64(driveKey!),
        'syncedToBlock': syncedToBlock,
      };
}

/// AES-GCM with [fixtureNonce] instead of a random one, so the private
/// fixtures are vectors. Only ever used to build fixtures.
class _FixedNonceCrypto extends ArDriveCrypto {
  @override
  Future<SecretBox> encrypt(Uint8List data, SecretKey key) =>
      AesGcm.with256bits().encrypt(data, secretKey: key, nonce: fixtureNonce);
}

final _codec = DriveStateEnvelopeCodec(crypto: _FixedNonceCrypto());

DriveStateProtection _protection(String privacy, Uint8List? key) =>
    DriveStateProtection.forDrive(
      privacy: privacy,
      driveKey: key == null ? null : SecretKey(key),
    ).protection!;

/// Real transaction ids are 43 characters of base64url over 32 random bytes.
/// From a fixed seed, so every run writes the same ones.
final _rng = Random(20261020);
String _txId() => base64Url
    .encode(List<int>.generate(32, (_) => _rng.nextInt(256)))
    .replaceAll('=', '');

/// Builds every fixture. Deterministic apart from gzip's timestamp.
Future<List<GoldenFixture>> buildGoldenFixtures() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final wallet = getTestWallet();
  final owner = await wallet.getAddress();

  final publicGood = await _produce(wallet, owner, DrivePrivacyTag.public);
  final privateGood = await _produce(wallet, owner, DrivePrivacyTag.private);
  final ghost = await _produce(
    wallet,
    owner,
    DrivePrivacyTag.public,
    withGhostFolder: true,
  );

  final publicReader = FixtureReader(
    ownerAddress: owner,
    privacy: DrivePrivacyTag.public,
    driveKey: null,
  );
  final privateReader = FixtureReader(
    ownerAddress: owner,
    privacy: DrivePrivacyTag.private,
    driveKey: fixtureDriveKey,
  );

  final fixtures = <GoldenFixture>[];

  Future<void> add(
    String name,
    String description, {
    required _Produced from,
    Uint8List? payload,
    List<String> edit = const [],
    Uint8List? body,
    FixtureReader? reader,
    Map<String, String?> retag = const {},
    String? uploadedBy,
    bool recountEntities = true,
  }) async {
    final isPrivate = from.privacy == DrivePrivacyTag.private;
    final readerState = reader ?? (isPrivate ? privateReader : publicReader);

    var plaintext = payload ?? from.plaintext;
    if (edit.isNotEmpty) plaintext = editArtifact(plaintext, edit);

    final Uint8List sealedBody;
    String? cipherIv;
    if (body != null) {
      sealedBody = body;
      cipherIv = from.cipherIv;
    } else if (identical(plaintext, from.plaintext)) {
      sealedBody = from.body;
      cipherIv = from.cipherIv;
    } else {
      final sealed = await _codec.seal(
        plaintext: plaintext,
        protection:
            _protection(from.privacy, isPrivate ? fixtureDriveKey : null),
      );
      sealedBody = sealed.envelope!.body;
      cipherIv = sealed.envelope!.cipherIvAsBase64;
    }

    final meta = _isSqlite(plaintext)
        ? artifactRow(plaintext, 'SELECT * FROM meta LIMIT 1')
        : null;
    final tags = _tags(
      blockStart: (meta?['blockStart'] as int?) ?? 0,
      blockEnd: (meta?['blockEnd'] as int?) ?? from.blockEnd,
      entityCount: recountEntities && meta != null
          ? entitiesIn(plaintext)
          : from.entityCount,
      dataStart: from.dataStart,
      dataEnd: from.dataEnd,
      cipherIv: isPrivate ? cipherIv : null,
      retag: retag,
    );

    final result = await _import(
      body: sealedBody,
      tags: tags,
      uploadedBy: uploadedBy ?? owner,
      reader: readerState,
    );

    fixtures.add(GoldenFixture(
      name: name,
      description: description,
      body: sealedBody,
      tags: tags,
      uploadedBy: uploadedBy ?? owner,
      reader: readerState,
      // Only where a reader can reach the payload: a body that was replaced
      // carries some other payload, or none.
      payloadSha256: (body == null || identical(body, from.plaintext)) &&
              _isSqlite(plaintext)
          ? await _sha256(plaintext)
          : null,
      outcome: result.outcome.name,
      detail: result.detail,
      tables: result.outcome.name == 'used' ? _tables(plaintext) : null,
    ));
  }

  // The producer's own output, unchanged.
  await add(
    'public-gzip',
    'A public drive with every optional column populated, as the producer '
        'publishes it: gzip, no cipher.',
    from: publicGood,
  );
  await add(
    'private-gzip',
    'The same drive, private: gzip, then AES-256-GCM under the drive key '
        'with a fixed nonce.',
    from: privateGood,
  );
  await add(
    'public-raw',
    'The public drive with no gzip: the body is the SQLite file itself.',
    from: publicGood,
    body: publicGood.plaintext,
  );
  await add(
    'ghost-parent',
    'A file whose parent folder no table carries, because the producer only '
        'knew it as a placeholder.',
    from: ghost,
  );
  await add(
    'drive-row-only',
    'Only the drive row: no folders, files, revisions or licences.',
    from: publicGood,
    edit: [
      'DELETE FROM folder_entries',
      'DELETE FROM file_entries',
      'DELETE FROM folder_revisions',
      'DELETE FROM file_revisions',
      'DELETE FROM licenses',
      'DELETE FROM transaction_statuses',
      'UPDATE meta SET entityCount = 1',
    ],
    // No block holds any of its data, which a producer says with -1.
    retag: {EntityTag.dataStart: '-1', EntityTag.dataEnd: '-1'},
  );
  await add(
    'private-cipher-iv-standard-base64',
    'The private drive with Cipher-IV in standard base64 with padding rather '
        'than base64url. Readers accept both.',
    from: privateGood,
    retag: {
      EntityTag.cipherIv: base64.encode(fixtureNonce),
    },
  );

  // The tags against the body and the reader.
  await add(
    'owner-mismatch',
    'Uploaded by a wallet that does not own the drive.',
    from: publicGood,
    uploadedBy: 'SomeOtherWalletAddress000000000000000000000',
  );
  await add(
    'drive-id-tag-mismatch',
    'The Drive-Id tag names a different drive from the one in the payload.',
    from: publicGood,
    retag: {EntityTag.driveId: '11111111-2222-4333-8444-555555555555'},
  );
  await add(
    'entity-count-tag-wrong',
    'Entity-Count is one more than the payload holds.',
    from: publicGood,
    retag: {EntityTag.entityCount: '${publicGood.entityCount + 1}'},
  );
  await add(
    'block-end-tag-above-payload',
    'Block-End claims more blocks than the payload accounts for.',
    from: publicGood,
    retag: {EntityTag.blockEnd: '${publicGood.blockEnd + 1000}'},
  );
  await add(
    'state-version-other-minor',
    'State-Version 0.1: a 0.x reader requires an exact match.',
    from: publicGood,
    retag: {EntityTag.stateVersion: '0.1'},
  );
  await add(
    'state-version-next-major',
    'State-Version 1.0, a major this reader does not implement.',
    from: publicGood,
    retag: {EntityTag.stateVersion: '1.0'},
  );
  await add(
    'state-version-malformed',
    'State-Version "1", which is not major.minor.',
    from: publicGood,
    retag: {EntityTag.stateVersion: '1'},
  );
  await add(
    'payload-version-other-minor',
    "The tag says the reader's version and meta.version says 0.1.",
    from: publicGood,
    edit: ["UPDATE meta SET version = '0.1'"],
  );
  await add(
    'cipher-tags-on-public',
    'A public drive whose entity carries Cipher and Cipher-IV.',
    from: publicGood,
    retag: {
      EntityTag.cipher: Cipher.aes256,
      EntityTag.cipherIv: utils.encodeBytesToBase64(fixtureNonce),
    },
  );
  await add(
    'cipher-tags-missing-on-private',
    'A private drive whose entity carries neither cipher tag.',
    from: privateGood,
    retag: {EntityTag.cipher: null, EntityTag.cipherIv: null},
  );
  await add(
    'cipher-iv-missing',
    'Cipher without Cipher-IV.',
    from: privateGood,
    retag: {EntityTag.cipherIv: null},
  );
  await add(
    'range-already-covered',
    'The reader has already synced the drive past Block-End, so the '
        'artifact would take it backwards. A reader at exactly Block-End '
        'still reads it: the same range can repair entities a sync skipped.',
    from: publicGood,
    reader: FixtureReader(
      ownerAddress: owner,
      privacy: DrivePrivacyTag.public,
      driveKey: null,
      syncedToBlock: publicGood.blockEnd + 1,
    ),
  );

  // The ciphertext.
  await add(
    'private-wrong-key',
    'Sealed under a different key from the one the reader holds.',
    from: privateGood,
    body: (await _codec.seal(
      plaintext: privateGood.plaintext,
      protection: _protection(
        DrivePrivacyTag.private,
        Uint8List.fromList(List<int>.filled(32, 7)),
      ),
    ))
        .envelope!
        .body,
  );
  await add(
    'private-ciphertext-truncated',
    'The last 10 bytes of the ciphertext are missing.',
    from: privateGood,
    body: Uint8List.sublistView(
        privateGood.body, 0, privateGood.body.length - 10),
  );
  await add(
    'private-auth-tag-flipped',
    'One bit of the 16-byte GCM authentication tag is flipped.',
    from: privateGood,
    body: Uint8List.fromList(privateGood.body)..last ^= 0x01,
  );

  // The bytes inside.
  await add(
    'not-gzip-or-sqlite',
    'A public body that is neither a gzip stream nor a SQLite file.',
    from: publicGood,
    body: Uint8List.fromList(utf8.encode('this is not a drive state')),
  );
  await add(
    'gzip-not-sqlite',
    'A gzip stream that inflates to something other than SQLite.',
    from: publicGood,
    body: Uint8List.fromList(
      GZipEncoder().encode(utf8.encode('this is not a drive state'))!,
    ),
  );
  await add(
    'gzip-bomb',
    'A gzip stream of zeros that inflates past 100 MiB. A reader stops at the '
        'first byte over the limit.',
    from: publicGood,
    body: Uint8List.fromList(
      GZipEncoder().encode(Uint8List(100 * 1024 * 1024 + 1), level: 9)!,
    ),
  );
  await add(
    'corrupt-page',
    'A page in the middle of the database is overwritten, so integrity_check '
        'does not return ok.',
    from: publicGood,
    payload: _corruptPage(publicGood.plaintext),
    recountEntities: false,
  );

  // The database's shape.
  await add(
    'application-id-wrong',
    'application_id is not 0x41724453.',
    from: publicGood,
    edit: ['PRAGMA application_id = 1'],
  );
  await add(
    'extra-table',
    'A tenth table.',
    from: publicGood,
    edit: ['CREATE TABLE notes (body TEXT)'],
  );
  await add(
    'view',
    'A view beside the nine tables.',
    from: publicGood,
    edit: ['CREATE VIEW names AS SELECT name FROM file_entries'],
  );
  await add(
    'trigger',
    'A trigger beside the nine tables.',
    from: publicGood,
    edit: [
      'CREATE TRIGGER t AFTER INSERT ON meta BEGIN SELECT 1; END',
    ],
  );
  await add(
    'index',
    'An index beside the nine tables.',
    from: publicGood,
    edit: ['CREATE INDEX file_names ON file_entries(name)'],
  );
  await add(
    'ddl-extra-space',
    "meta's CREATE TABLE differs from the format's by one space.",
    from: publicGood,
    edit: [
      'PRAGMA writable_schema = ON',
      "UPDATE sqlite_master SET sql = replace(sql, 'version TEXT', "
          "'version  TEXT') WHERE name = 'meta'",
      'PRAGMA writable_schema = OFF',
    ],
  );
  await add(
    'meta-two-rows',
    'meta holds two rows.',
    from: publicGood,
    edit: ['INSERT INTO meta SELECT * FROM meta'],
  );
  await add(
    'coverage-reversed',
    'blockStart is above blockEnd, in the payload and the tags alike.',
    from: publicGood,
    edit: ['UPDATE meta SET blockStart = blockEnd + 1'],
  );
  await add(
    'block-start-negative',
    'blockStart is -1, in the payload and the tags alike.',
    from: publicGood,
    edit: ['UPDATE meta SET blockStart = -1'],
  );

  // The rows.
  await add(
    'text-in-integer-column',
    "A file's size is the text 'large'.",
    from: publicGood,
    edit: ["UPDATE file_entries SET size = 'large' WHERE rowid = 1"],
  );
  await add(
    'date-out-of-range',
    "A file's dateCreated is far past any real date.",
    from: publicGood,
    edit: [
      'UPDATE file_entries SET dateCreated = 99999999999999 WHERE rowid = 1',
    ],
  );
  await add(
    'file-listed-twice',
    'One file has two rows in file_entries.',
    from: publicGood,
    edit: [
      'INSERT INTO file_entries SELECT * FROM file_entries WHERE rowid = 1',
      'UPDATE meta SET entityCount = entityCount + 1',
    ],
  );
  await add(
    'file-from-another-drive',
    'A file row names a different driveId.',
    from: publicGood,
    edit: [
      "UPDATE file_entries SET driveId = '11111111-2222-4333-8444-555555555555' "
          'WHERE rowid = 1',
    ],
  );
  await add(
    'licence-from-another-drive',
    'A licence row names a different driveId.',
    from: publicGood,
    edit: [
      "UPDATE licenses SET driveId = '11111111-2222-4333-8444-555555555555'",
    ],
  );
  await add(
    'status-confirmed',
    "transaction_statuses lists a transaction as 'confirmed', which a "
        'producer never writes.',
    from: publicGood,
    edit: [
      'INSERT INTO transaction_statuses (id, status) '
          "SELECT metadataTxId, 'confirmed' FROM file_revisions LIMIT 1",
    ],
  );
  await add(
    'status-metadata-pending',
    "transaction_statuses lists a metadata transaction as 'pending'.",
    from: publicGood,
    edit: [
      'INSERT INTO transaction_statuses (id, status) '
          "SELECT metadataTxId, 'pending' FROM file_revisions LIMIT 1",
    ],
  );
  await add(
    'folder-cycle',
    'Two folders are each the parent of the other.',
    from: publicGood,
    edit: [
      "UPDATE folder_entries SET parentFolderId = '1a2b3c4d-0002-4000-8000-0000000a7c41' "
          "WHERE id = '1a2b3c4d-0001-4000-8000-00000000d0c5'",
      "UPDATE folder_entries SET parentFolderId = '1a2b3c4d-0001-4000-8000-00000000d0c5' "
          "WHERE id = '1a2b3c4d-0002-4000-8000-0000000a7c41'",
    ],
  );
  await add(
    'root-folder-missing',
    "The drive's root folder is in no table.",
    from: publicGood,
    edit: [
      "DELETE FROM folder_entries WHERE id = '$fixtureRootFolderId'",
      "DELETE FROM folder_revisions WHERE folderId = '$fixtureRootFolderId'",
      'UPDATE meta SET entityCount = entityCount - 1',
    ],
  );

  return fixtures;
}

/// A producer's output for one seeded drive.
class _Produced {
  _Produced({
    required this.privacy,
    required this.plaintext,
    required this.body,
    required this.cipherIv,
    required this.blockEnd,
    required this.entityCount,
    required this.dataStart,
    required this.dataEnd,
  });

  final String privacy;
  final Uint8List plaintext;
  final Uint8List body;
  final String? cipherIv;
  final int blockEnd;
  final int entityCount;
  final int dataStart;
  final int dataEnd;
}

/// Seeds a drive, runs the app's own producer over it, and checks that the
/// tags [_tags] builds for every other fixture are the ones it wrote.
Future<_Produced> _produce(
  Wallet wallet,
  String owner,
  String privacy, {
  bool withGhostFolder = false,
}) async {
  final db = getTestDb();
  try {
    await _seedDrive(db,
        owner: owner, privacy: privacy, ghost: withGhostFolder);

    final service = DriveStateCreationService(
      driveDao: db.driveDao,
      skipSource: const _CleanSkipSource(),
      codec: _codec,
      newArtifactId: () => fixtureDriveStateId,
      appVersion: () async => fixtureAppVersion,
    );
    final result = await service.prepare(
      driveId: fixtureDriveId,
      driveKey: privacy == DrivePrivacyTag.private
          ? SecretKey(fixtureDriveKey)
          : null,
      wallet: wallet,
    );
    if (result.isRefused) {
      throw StateError('the producer refused the fixture drive: '
          '${result.refusal} ${result.reason}');
    }

    final entity = result.artifact!.entity;
    final body = entity.data!;
    final opened = await _codec.open(
      envelope: entity.cipherIv == null
          ? DriveStateEnvelope.inTheClear(body: body)
          : DriveStateEnvelope.encrypted(
              body: body,
              cipherIv: utils.decodeBase64ToBytes(entity.cipherIv!),
            ),
      protection: _protection(
        privacy,
        privacy == DrivePrivacyTag.private ? fixtureDriveKey : null,
      ),
    );

    final produced = _Produced(
      privacy: privacy,
      plaintext: opened.plaintext!,
      body: body,
      cipherIv: entity.cipherIv,
      blockEnd: entity.blockEnd!,
      entityCount: entity.entityCount!,
      dataStart: entity.dataStart!,
      dataEnd: entity.dataEnd!,
    );

    // The producer's own tags, against the builder every other fixture uses.
    final item = DataItem.withBlobData(data: body);
    entity.addEntityTagsToTransaction(item);
    final written = [
      for (final t in item.tags)
        (
          name: utils.decodeBase64ToString(t.name),
          value: utils.decodeBase64ToString(t.value),
        ),
    ];
    final built = _tags(
      blockStart: 0,
      blockEnd: produced.blockEnd,
      entityCount: produced.entityCount,
      dataStart: produced.dataStart,
      dataEnd: produced.dataEnd,
      cipherIv: produced.cipherIv,
    ).sublist(0, written.length);
    if (jsonEncode(_asJson(built)) != jsonEncode(_asJson(written))) {
      throw StateError('the fixture tags drifted from the producer\'s:\n'
          '${_asJson(written)}\n${_asJson(built)}');
    }

    return produced;
  } finally {
    await db.close();
  }
}

List<Map<String, String>> _asJson(List<({String name, String value})> tags) => [
      for (final t in tags) {'name': t.name, 'value': t.value}
    ];

/// The tags the producer writes, then the application tags it adds, with
/// [retag] replacing a value or, given null, removing the tag.
List<({String name, String value})> _tags({
  required int blockStart,
  required int blockEnd,
  required int entityCount,
  required int dataStart,
  required int dataEnd,
  required String? cipherIv,
  Map<String, String?> retag = const {},
}) {
  final tags = <String, String>{
    EntityTag.arFs: '0.15',
    EntityTag.entityType: EntityTypeTag.driveState,
    EntityTag.driveId: fixtureDriveId,
    EntityTag.driveStateId: fixtureDriveStateId,
    EntityTag.stateVersion: artifactFormatVersion,
    EntityTag.contentType: ContentType.octetStream,
    EntityTag.blockStart: '$blockStart',
    EntityTag.blockEnd: '$blockEnd',
    EntityTag.dataStart: '$dataStart',
    EntityTag.dataEnd: '$dataEnd',
    EntityTag.entityCount: '$entityCount',
    if (cipherIv != null) EntityTag.cipher: Cipher.aes256,
    if (cipherIv != null) EntityTag.cipherIv: cipherIv,
    EntityTag.appName: 'ArDrive-App',
    EntityTag.appPlatform: 'Web',
    EntityTag.appVersion: fixtureAppVersion,
    EntityTag.unixTime: '$fixtureUnixTime',
  };
  for (final entry in retag.entries) {
    if (entry.value == null) {
      tags.remove(entry.key);
    } else {
      tags[entry.key] = entry.value!;
    }
  }
  return [
    for (final e in tags.entries) (name: e.key, value: e.value),
  ];
}

/// Runs this app's importer over a fixture, into an empty client that holds
/// the drive the way [reader] describes.
Future<DriveStateImportResult> _import({
  required Uint8List body,
  required List<({String name, String value})> tags,
  required String uploadedBy,
  required FixtureReader reader,
}) async {
  final db = getTestDb();
  try {
    final isPrivate = reader.privacy == DrivePrivacyTag.private;
    await db.into(db.drives).insert(
          DrivesCompanion.insert(
            id: fixtureDriveId,
            rootFolderId: fixtureRootFolderId,
            ownerAddress: reader.ownerAddress,
            name: 'A drive the reader has not synced',
            privacy: reader.privacy,
            encryptedKey: isPrivate
                ? Value(Uint8List.fromList([1, 2, 3, 4]))
                : const Value(null),
            keyEncryptionIv: isPrivate
                ? Value(Uint8List.fromList([5, 6, 7]))
                : const Value(null),
            driveKeyGenerated: Value(isPrivate),
            lastBlockHeight: Value(reader.syncedToBlock),
            lastUpdated: Value(DateTime.utc(2020)),
          ),
        );

    final tagMap = <String, String>{};
    for (final t in tags) {
      tagMap.putIfAbsent(t.name, () => t.value);
    }

    return await DriveStateImporter(db.driveDao).import(
      candidate: DriveStateArtifactCandidate(
        txId: fixtureTxId,
        ownerAddress: uploadedBy,
        tags: tagMap,
      ),
      body: body,
      protection: _protection(reader.privacy, reader.driveKey),
      expectedOwnerAddress: reader.ownerAddress,
    );
  } finally {
    await db.close();
  }
}

class _CleanSkipSource implements DriveStateSyncSkipSource {
  const _CleanSkipSource();

  @override
  DriveStateSyncSkipStatus statusFor(String driveId) =>
      const DriveStateSyncSkipStatus.clean();
}

bool _isSqlite(Uint8List bytes) =>
    bytes.length > 16 &&
    utf8.decode(bytes.sublist(0, 15), allowMalformed: true) ==
        'SQLite format 3';

Future<String> _sha256(List<int> bytes) async => (await Sha256().hash(bytes))
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

/// Every table of an artifact, in the format's order, rows in `rowid` order.
Map<String, List<Map<String, Object?>>> _tables(Uint8List bytes) {
  final dir = Directory.systemTemp.createTempSync('drive-state-fixture');
  try {
    final path = '${dir.path}/artifact.db';
    File(path).writeAsBytesSync(bytes);
    final db = raw.sqlite3.open(path, mode: raw.OpenMode.readOnly);
    try {
      return {
        for (final table in artifactSchema.keys)
          table: [
            for (final row in db.select('SELECT * FROM $table ORDER BY rowid'))
              Map<String, Object?>.from(row),
          ],
      };
    } finally {
      db.dispose();
    }
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// Overwrites the middle of the last page, which holds rows, so the file
/// still opens and `integrity_check` is what finds the damage.
Uint8List _corruptPage(Uint8List plaintext) {
  final pageSize = (plaintext[16] << 8) | plaintext[17];
  final lastPage = plaintext.length - pageSize;
  final corrupt = Uint8List.fromList(plaintext);
  for (var i = lastPage + 8; i < lastPage + pageSize ~/ 2; i++) {
    corrupt[i] = 0xa5;
  }
  return corrupt;
}

/// A drive with every column a reader has to carry: custom metadata and tags,
/// a thumbnail, ArNS names, a pin, hidden items, a file moved and renamed
/// across three revisions, a licence, a data transaction still pending and
/// one that failed.
Future<void> _seedDrive(
  Database db, {
  required String owner,
  required String privacy,
  required bool ghost,
}) async {
  // Seconds, as Drift stores DATETIME.
  const t0 = 1700000000;
  final isPrivate = privacy == DrivePrivacyTag.private;

  Future<void> sql(String statement, [List<Object?> args = const []]) =>
      db.customStatement(statement, args);

  Future<void> tx(String id, String status, int date) => sql(
        'INSERT INTO network_transactions (id, status, dateCreated, '
        'transactionDateCreated) VALUES (?, ?, ?, ?)',
        [id, status, date, date],
      );

  await sql(
    'INSERT INTO drives (id, rootFolderId, ownerAddress, name, privacy, '
    'encryptedKey, keyEncryptionIv, driveKeyGenerated, syncCursor, '
    'lastBlockHeight, bundledIn, customJsonMetadata, customGQLTags, isHidden, '
    'signatureType, dateCreated, lastUpdated) '
    "VALUES (?, ?, ?, 'Fixture drive', ?, ?, ?, ?, 'producer-cursor', "
    '1500000, ?, ?, ?, 0, ?, ?, ?)',
    [
      fixtureDriveId,
      fixtureRootFolderId,
      owner,
      privacy,
      isPrivate ? Uint8List.fromList(List.filled(32, 9)) : null,
      isPrivate ? Uint8List.fromList(List.filled(12, 3)) : null,
      isPrivate ? 1 : 0,
      _txId(),
      '{"project":"fixtures"}',
      '[{"name":"Fixture-Tag","value":"drive"}]',
      isPrivate ? '1' : null,
      t0,
      t0 + 500,
    ],
  );

  Future<void> driveRevision(String name, String action, int date) async {
    final id = _txId();
    await tx(id, 'confirmed', date);
    await sql(
      'INSERT INTO drive_revisions (driveId, rootFolderId, ownerAddress, '
      'name, privacy, metadataTxId, dateCreated, action, bundledIn, '
      'customJsonMetadata, customGQLTags, isHidden) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)',
      [
        fixtureDriveId,
        fixtureRootFolderId,
        owner,
        name,
        privacy,
        id,
        date,
        action,
        _txId(),
        '{"project":"fixtures"}',
        '[{"name":"Fixture-Tag","value":"drive"}]',
      ],
    );
  }

  await driveRevision('Fixture drive (draft)', 'create', t0);
  await driveRevision('Fixture drive', 'rename', t0 + 500);

  Future<void> folder(
    String id,
    String? parent,
    List<({String name, String action, int date})> revisions, {
    bool hidden = false,
  }) async {
    for (final r in revisions) {
      final txId = _txId();
      await tx(txId, 'confirmed', r.date);
      await sql(
        'INSERT INTO folder_revisions (folderId, driveId, name, '
        'parentFolderId, metadataTxId, dateCreated, action, '
        'customJsonMetadata, customGQLTags, isHidden) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          fixtureDriveId,
          r.name,
          parent,
          txId,
          r.date,
          r.action,
          hidden ? '{"why":"old"}' : null,
          hidden ? '[{"name":"Fixture-Tag","value":"folder"}]' : null,
          hidden && r.action == 'hide' ? 1 : 0,
        ],
      );
    }
    final last = revisions.last;
    await sql(
      'INSERT INTO folder_entries (id, driveId, name, parentFolderId, path, '
      'dateCreated, lastUpdated, isGhost, customJsonMetadata, customGQLTags, '
      'isHidden) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?)',
      [
        id,
        fixtureDriveId,
        last.name,
        parent,
        '',
        revisions.first.date,
        last.date,
        hidden ? '{"why":"old"}' : null,
        hidden ? '[{"name":"Fixture-Tag","value":"folder"}]' : null,
        hidden ? 1 : 0,
      ],
    );
  }

  await folder(fixtureRootFolderId, null, [
    (name: 'Fixture drive', action: 'create', date: t0),
  ]);
  await folder('1a2b3c4d-0001-4000-8000-00000000d0c5', fixtureRootFolderId, [
    (name: 'Docs', action: 'create', date: t0 + 10),
    (name: 'Documents', action: 'rename', date: t0 + 20),
  ]);
  await folder(
    '1a2b3c4d-0002-4000-8000-0000000a7c41',
    fixtureRootFolderId,
    [
      (name: 'Archive', action: 'create', date: t0 + 30),
      (name: 'Archive', action: 'hide', date: t0 + 40),
    ],
    hidden: true,
  );

  if (ghost) {
    // A folder this client only knows as a placeholder: no revision vouches
    // for it, so the producer does not publish it, and its file arrives with
    // a parent no table carries.
    await sql(
      'INSERT INTO folder_entries (id, driveId, name, parentFolderId, path, '
      'dateCreated, lastUpdated, isGhost, isHidden) '
      "VALUES ('1a2b3c4d-0003-4000-8000-0000000960a7', ?, '1a2b3c4d-0003-4000-8000-0000000960a7', ?, '', ?, ?, 1, 0)",
      [fixtureDriveId, fixtureRootFolderId, t0, t0],
    );
  }

  Future<void> file(
    String id,
    List<
            ({
              String name,
              String parent,
              String action,
              int date,
            })>
        revisions, {
    required String dataTxId,
    String dataStatus = 'confirmed',
    String? licenseTxId,
    String? thumbnail,
    String? pinnedOwner,
    String? assignedNames,
    String? fallbackTxId,
    String? originalOwner,
    String? importSource,
    String? customJson,
    String? customTags,
    bool hidden = false,
    int size = 1024,
  }) async {
    await tx(dataTxId, dataStatus, revisions.first.date);
    final bundledIn = _txId();
    for (final r in revisions) {
      final txId = _txId();
      await tx(txId, 'confirmed', r.date);
      await sql(
        'INSERT INTO file_revisions (fileId, driveId, name, parentFolderId, '
        'size, lastModifiedDate, dataContentType, metadataTxId, dataTxId, '
        'licenseTxId, thumbnail, bundledIn, dateCreated, customJsonMetadata, '
        'customGQLTags, action, pinnedDataOwnerAddress, isHidden, '
        'assignedNames, fallbackTxId, originalOwner, importSource) '
        "VALUES (?, ?, ?, ?, ?, ?, 'application/pdf', ?, ?, ?, ?, ?, ?, ?, ?, "
        '?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          fixtureDriveId,
          r.name,
          r.parent,
          size,
          t0 - 86400,
          txId,
          dataTxId,
          licenseTxId,
          thumbnail,
          bundledIn,
          r.date,
          customJson,
          customTags,
          r.action,
          pinnedOwner,
          hidden && r == revisions.last ? 1 : 0,
          assignedNames,
          fallbackTxId,
          originalOwner,
          importSource,
        ],
      );
    }
    final last = revisions.last;
    await sql(
      'INSERT INTO file_entries (id, driveId, name, parentFolderId, path, '
      'size, lastModifiedDate, dataContentType, dataTxId, licenseTxId, '
      'bundledIn, thumbnail, pinnedDataOwnerAddress, customJsonMetadata, '
      'customGQLTags, isHidden, dateCreated, lastUpdated, assignedNames, '
      'fallbackTxId, originalOwner, importSource) '
      "VALUES (?, ?, ?, ?, '', ?, ?, 'application/pdf', ?, ?, ?, ?, ?, ?, ?, "
      '?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        fixtureDriveId,
        last.name,
        last.parent,
        size,
        t0 - 86400,
        dataTxId,
        licenseTxId,
        bundledIn,
        thumbnail,
        pinnedOwner,
        customJson,
        customTags,
        hidden ? 1 : 0,
        revisions.first.date,
        last.date,
        assignedNames,
        fallbackTxId,
        originalOwner,
        importSource,
      ],
    );
  }

  // Moved and renamed: three revisions.
  final reportData = _txId();
  final reportLicence = _txId();
  await file(
    '2b3c4d5e-0001-4000-8000-0000000e9077',
    [
      (
        name: 'draft.pdf',
        parent: fixtureRootFolderId,
        action: 'create',
        date: t0 + 100
      ),
      (
        name: 'report.pdf',
        parent: fixtureRootFolderId,
        action: 'rename',
        date: t0 + 110
      ),
      (
        name: 'report.pdf',
        parent: '1a2b3c4d-0001-4000-8000-00000000d0c5',
        action: 'move',
        date: t0 + 120
      ),
    ],
    dataTxId: reportData,
    licenseTxId: reportLicence,
    thumbnail: '{"variants":[{"name":"thumbnail","txId":"${_txId()}",'
        '"size":2048,"width":256,"height":256}]}',
    assignedNames: '{"assignedNames":["report_fixtures"]}',
    customJson: '{"department":"finance"}',
    customTags: '[{"name":"Fixture-Tag","value":"report"}]',
  );
  await tx(reportLicence, 'confirmed', t0 + 100);
  await sql(
    'INSERT INTO licenses (fileId, driveId, dataTxId, licenseTxType, '
    'licenseTxId, bundledIn, dateCreated, licenseType, customGQLTags) '
    "VALUES ('2b3c4d5e-0001-4000-8000-0000000e9077', ?, ?, 'assertion', ?, ?, ?, 'ccBy', ?)",
    [
      fixtureDriveId,
      reportData,
      reportLicence,
      _txId(),
      t0 + 100,
      '{"Commercial-Use":"Allowed"}',
    ],
  );

  // A pin: data owned by another wallet, with a fallback and an import source.
  await file(
    '2b3c4d5e-0002-4000-8000-0000000b1a7e',
    [
      (
        name: 'pinned.jpg',
        parent: fixtureRootFolderId,
        action: 'create',
        date: t0 + 200
      ),
    ],
    dataTxId: _txId(),
    pinnedOwner: 'PinnedDataOwnerAddress00000000000000000000',
    fallbackTxId: _txId(),
    originalOwner: 'OriginalOwnerAddress0000000000000000000000',
    importSource: 'arweave',
  );

  // Hidden, in the hidden folder.
  await file(
    '2b3c4d5e-0003-4000-8000-0000000d1dde',
    [
      (
        name: 'old.txt',
        parent: '1a2b3c4d-0002-4000-8000-0000000a7c41',
        action: 'create',
        date: t0 + 300
      ),
      (
        name: 'old.txt',
        parent: '1a2b3c4d-0002-4000-8000-0000000a7c41',
        action: 'hide',
        date: t0 + 310
      ),
    ],
    dataTxId: _txId(),
    hidden: true,
    size: 12,
  );

  // Data not yet seen confirmed, and data that failed.
  await file(
    '2b3c4d5e-0004-4000-8000-0000000be4d1',
    [
      (
        name: 'uploading.mov',
        parent: '1a2b3c4d-0001-4000-8000-00000000d0c5',
        action: 'create',
        date: t0 + 400
      ),
    ],
    dataTxId: _txId(),
    dataStatus: 'pending',
    size: 50 * 1024 * 1024,
  );
  await file(
    '2b3c4d5e-0005-4000-8000-0000000fa11e',
    [
      (
        name: 'failed.zip',
        parent: fixtureRootFolderId,
        action: 'create',
        date: t0 + 410
      ),
    ],
    dataTxId: _txId(),
    dataStatus: 'failed',
  );

  if (ghost) {
    await file(
      '2b3c4d5e-0006-4000-8000-0000000e9a05',
      [
        (
          name: 'orphan.txt',
          parent: '1a2b3c4d-0003-4000-8000-0000000960a7',
          action: 'create',
          date: t0 + 420
        ),
      ],
      dataTxId: _txId(),
    );
  }
}
