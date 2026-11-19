import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/core/crypto/file_keys.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_sync_skip_status.dart';
import 'package:ardrive/drive_state/domain/drive_state_uploader.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_export.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/shared_file/shared_file_key_session.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/publication/data/publication_source.dart';
import 'package:ardrive/publication/data/publication_uploader.dart';
import 'package:ardrive/publication/domain/private_page.dart';
import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/domain/publication_publisher.dart';
import 'package:ardrive/publication/domain/publication_scope.dart';
import 'package:ardrive/publication/domain/sealed/seal_codec.dart';
import 'package:ardrive/publication/presentation/publication_loader/publication_loader_cubit.dart'
    hide PublicationFailure;
import 'package:ardrive/utils/session_key_value_store.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' show decodeBase64ToString;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../test_utils/utils.dart';

const _drive = 'd1d1d1d1-0000-4000-8000-000000000001';
const _root = 'a0a0a0a0-0000-4000-8000-000000000001';
const _docs = 'b0b0b0b0-0000-4000-8000-000000000002';
const _hiddenFolder = 'c0c0c0c0-0000-4000-8000-000000000003';
const _diary = 'f0000001-0000-4000-8000-000000000001';
const _budget = 'f0000002-0000-4000-8000-000000000002';
const _hiddenFile = 'f0000003-0000-4000-8000-000000000003';
const _underHidden = 'f0000004-0000-4000-8000-000000000004';
const _renamed = 'f0000005-0000-4000-8000-000000000005';
const _ghostFolder = 'e0e0e0e0-0000-4000-8000-000000000005';
const _underGhost = 'f0000006-0000-4000-8000-000000000006';
const _failed = 'f0000007-0000-4000-8000-000000000007';
const _pending = 'f0000008-0000-4000-8000-000000000008';

/// Every name in the drive, which nothing public may carry.
const _names = [
  'Secret Drive Name',
  'Docs Folder',
  'Hidden Plans',
  'Diary Entry.txt',
  'budget-2026.xlsx',
  'secret-hidden.txt',
  'under-hidden.txt',
  'Old Name.txt',
  'New Name.txt',
  'failed-upload.txt',
  'pending-upload.txt',
];

const _password = 'tide lantern';

class _Clean implements DriveStateSyncSkipSource {
  @override
  DriveStateSyncSkipStatus statusFor(String driveId) =>
      const DriveStateSyncSkipStatus.clean();
}

class _NoSnapshots implements DriveStateUploader {
  @override
  Future<DriveStateUploadResult> publish(PreparedDriveStateArtifact artifact,
          {required UploadMethod method}) =>
      throw StateError('a private page uploads no snapshot');
}

/// Keeps what would be posted; signs for real, so IDs are real.
class _Recording extends PublicationUploader {
  _Recording()
      : super(
          arweave: MockArweaveService(),
          turboUploadService: MockTurboUploadService(),
        );

  final posted = <DataItem>[];

  /// The sealed IVs of every publication.json asked to be signed.
  final sealedIvs = <String>[];

  /// The wallet refuses the next publication.json, as it may mid-publish.
  bool refuseNextSettings = false;

  @override
  Future<DataItem> sign(PublicationItem item, Wallet wallet) {
    if (item.name == 'publication.json') {
      sealedIvs.add((jsonDecode(utf8.decode(item.data))['sealed'] as Map)['iv']
          as String);
      if (refuseNextSettings) {
        refuseNextSettings = false;
        throw StateError('the wallet said no');
      }
    }
    return super.sign(item, wallet);
  }

  @override
  Future<void> postToTurbo(DataItem item, Wallet wallet) async =>
      posted.add(item);
}

Map<String, String> _tags(DataItem item) => {
      for (final t in item.tags)
        decodeBase64ToString(t.name): decodeBase64ToString(t.value),
    };

/// A private drive holding a folder, a hidden folder, a hidden file, a
/// file renamed once, and two files whose latest upload failed or is pending.
Future<void> _seed(Database db, String owner) async {
  const t0 = 1790000000;
  var n = 0;
  // One count per ID: distinct for the first 256.
  String txId() {
    final k = ++n;
    return base64Url
        .encode(List.generate(32, (i) => (i * 7 + k * 13) % 256))
        .replaceAll('=', '');
  }

  Future<void> sql(String s, [List<Object?> a = const []]) =>
      db.customStatement(s, a);
  Future<void> tx(String id, int date, {String status = 'confirmed'}) => sql(
      'INSERT OR IGNORE INTO network_transactions (id, status, dateCreated, '
      'transactionDateCreated) VALUES (?, ?, ?, ?)',
      [id, status, date, date]);

  await sql(
    'INSERT INTO drives (id, rootFolderId, ownerAddress, name, privacy, '
    'encryptedKey, keyEncryptionIv, driveKeyGenerated, syncCursor, '
    'lastBlockHeight, isHidden, signatureType, dateCreated, lastUpdated) '
    "VALUES (?, ?, ?, 'Secret Drive Name', 'private', ?, ?, 1, 'c', 100, 0, "
    "'1', ?, ?)",
    [_drive, _root, owner, Uint8List(32), Uint8List(12), t0, t0],
  );
  final driveRev = txId();
  await tx(driveRev, t0);
  await sql(
    'INSERT INTO drive_revisions (driveId, rootFolderId, ownerAddress, name, '
    'privacy, metadataTxId, dateCreated, action, isHidden) VALUES (?, ?, ?, '
    "'Secret Drive Name', 'private', ?, ?, 'create', 0)",
    [_drive, _root, owner, driveRev, t0],
  );
  Future<void> folder(String id, String? parent, String name,
      {bool hidden = false}) async {
    final rev = txId();
    await tx(rev, t0);
    await sql(
      'INSERT INTO folder_revisions (folderId, driveId, name, parentFolderId, '
      'metadataTxId, dateCreated, action, isHidden) VALUES (?, ?, ?, ?, ?, ?, '
      "'create', ?)",
      [id, _drive, name, parent, rev, t0, hidden ? 1 : 0],
    );
    await sql(
      'INSERT INTO folder_entries (id, driveId, name, parentFolderId, path, '
      "dateCreated, lastUpdated, isGhost, isHidden) VALUES (?, ?, ?, ?, '', "
      '?, ?, 0, ?)',
      [id, _drive, name, parent, t0, t0, hidden ? 1 : 0],
    );
  }

  Future<void> file(String id, String parent, List<String> names,
      {bool hidden = false,
      String dataStatus = 'confirmed',
      String metadataStatus = 'confirmed'}) async {
    final data = txId();
    await tx(data, t0, status: dataStatus);
    for (var i = 0; i < names.length; i++) {
      final rev = txId();
      await tx(rev, t0 + i, status: metadataStatus);
      await sql(
        'INSERT INTO file_revisions (fileId, driveId, name, parentFolderId, '
        'size, lastModifiedDate, dataContentType, metadataTxId, dataTxId, '
        'bundledIn, dateCreated, action, isHidden) VALUES (?, ?, ?, ?, 10, ?, '
        "'text/plain', ?, ?, ?, ?, ?, ?)",
        [
          id, _drive, names[i], parent, t0, rev, data, txId(), t0 + i, //
          i == 0 ? 'create' : 'rename', hidden ? 1 : 0,
        ],
      );
    }
    await sql(
      'INSERT INTO file_entries (id, driveId, name, parentFolderId, path, '
      'size, lastModifiedDate, dataContentType, dataTxId, isHidden, '
      "dateCreated, lastUpdated) VALUES (?, ?, ?, ?, '', 10, ?, 'text/plain', "
      '?, ?, ?, ?)',
      [id, _drive, names.last, parent, t0, data, hidden ? 1 : 0, t0, t0],
    );
  }

  await folder(_root, null, 'Secret Drive Name');
  await folder(_docs, _root, 'Docs Folder');
  await folder(_hiddenFolder, _root, 'Hidden Plans', hidden: true);
  await file(_diary, _root, ['Diary Entry.txt']);
  await file(_budget, _docs, ['budget-2026.xlsx']);
  await file(_hiddenFile, _root, ['secret-hidden.txt'], hidden: true);
  await file(_underHidden, _hiddenFolder, ['under-hidden.txt']);
  await file(_renamed, _docs, ['Old Name.txt', 'New Name.txt']);
  // A folder this client never read: no revision, only a placeholder row.
  await sql(
    'INSERT INTO folder_entries (id, driveId, name, parentFolderId, path, '
    "dateCreated, lastUpdated, isGhost, isHidden) VALUES (?, ?, ?, ?, '', "
    '?, ?, 1, 0)',
    [_ghostFolder, _drive, _ghostFolder, _root, t0, t0],
  );
  await file(_underGhost, _ghostFolder, ['in-ghost.txt']);
  await file(_failed, _root, ['failed-upload.txt'], dataStatus: 'failed');
  await file(_pending, _docs, ['pending-upload.txt'],
      metadataStatus: 'pending');
}

void main() {
  final wallet = getTestWallet();
  late String owner;
  late Database ownerDb;
  final driveKey = Uint8List.fromList(List.generate(32, (i) => i + 1));

  const release = PublicationRelease(
    manifestId: 'RELEASE_MANIFEST_00000000000000000000000000',
    manifest: {
      'manifest': 'arweave/paths',
      'version': '0.2.0',
      'index': {'path': 'index.html'},
      'paths': {
        'index.html': {'id': 'RELEASE_INDEX'},
        'main.dart.js': {'id': 'MAIN'},
      },
    },
    indexHtml:
        '<!DOCTYPE html>\n<html>\n  <head>\n    <meta charset="UTF-8" />\n'
        '    <title>ArDrive</title>\n  </head>\n  <body>\n  </body>\n</html>\n',
    version: '3.1.0',
    publicationVersion: 3,
  );

  setUpAll(() async {
    PackageInfo.setMockInitialValues(
      appName: 'ArDrive',
      packageName: 'ardrive',
      version: '3.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
    owner = await wallet.getAddress();
  });

  setUp(() async {
    ownerDb = getTestDb();
    await _seed(ownerDb, owner);
  });

  tearDown(() async {
    PublicationContents.open = null;
    await ownerDb.close();
  });

  /// Publishes a private page of [scopeRoot] and returns what was posted.
  Future<({List<DataItem> posted, PrivatePagePlan plan})> publish({
    required String scopeRoot,
    String? password,
    String title = '',
    _Recording? recording,
  }) async {
    final catalogKey = secureRandomBytes(32);
    final prepared = await DriveStateCreationService(
      driveDao: ownerDb.driveDao,
      skipSource: _Clean(),
      appVersion: () async => '3.1.0',
    ).prepare(
      driveId: _drive,
      driveKey: null,
      wallet: wallet,
      pageScope: ArtifactScope(scopeRoot),
      catalogKey: SecretKey(catalogKey),
    );
    expect(prepared.isRefused, isFalse, reason: prepared.reason);
    final catalog = prepared.artifact!;
    const publicationId = '7a8b9c0d-1e2f-4a3b-8c4d-5e6f7a8b9c0d';
    final publicationKey = secureRandomBytes(32);
    final plan = PrivatePagePlan(
      catalog: catalog,
      catalogKey: catalogKey,
      publicationKey: publicationKey,
      slots: await pageSlots(
        publicationKey: publicationKey,
        publicationId: publicationId,
        driveKey: driveKey,
        password: password,
        settings: const Argon2Settings(m: 8192, t: 1, p: 1),
      ),
      fileKeys: {
        for (final f in catalog.files) f.id: b64u(secureRandomBytes(32)),
      },
      rootFolderId: _root,
    );
    final uploader = recording ?? _Recording();
    final publisher = PublicationPublisher(
      uploader: uploader,
      driveStateUploader: _NoSnapshots(),
      repository: PublicationRepository(
        graphQLRetry: MockGraphQLRetry(),
        gatewayUrl: () => 'https://turbo-gateway.com',
      ),
      gatewayUrl: () => 'https://turbo-gateway.com',
      client: MockClient((_) async => http.Response('', 200)),
      now: () => DateTime.utc(2026, 11, 18, 12),
    );
    final job = PublicationJob(
      publicationId: publicationId,
      driveId: _drive,
      rootFolderId: _root,
      scope: scopeRoot == _root
          ? const PublicationDriveScope()
          : PublicationFolderScope(scopeRoot),
      privacy: 'private',
      owner: owner,
      ownerName: null,
      title: title,
      description: '',
      keywords: const [],
      license: null,
      icon: null,
      cover: null,
      social: null,
      privatePage: plan,
      snapshot: const NoSnapshot(),
      release: release,
      files: const [],
      fileCount: 0,
      labels: const PublicationLabels(
        filesPage: 'All files',
        openPage: 'Open',
        moreFiles: 'And {count} more.',
      ),
      method: UploadMethod.turbo,
    );
    try {
      await publisher.publish(job, wallet);
    } on PublicationFailure {
      // Try again, with the same job, as the dialog does.
      await publisher.publish(job, wallet);
    }
    return (posted: uploader.posted, plan: plan);
  }

  /// The page's own parts, by manifest path.
  Map<String, Uint8List> partsOf(List<DataItem> posted) {
    final manifest = posted.last;
    final paths = (jsonDecode(utf8.decode(manifest.data))['paths'] as Map)
        .cast<String, dynamic>();
    final byId = {for (final item in posted) item.id: item};
    return {
      for (final MapEntry(:key, :value) in paths.entries)
        if (byId[value['id']] case final item?) key: item.data,
    };
  }

  /// Opens [parts] in a fresh viewer, as a visitor would.
  Future<(PublicationLoaderCubit, Database, FileKeys)> open(
    Map<String, Uint8List> parts, {
    String? linkKey,
  }) async {
    final db = getTestDb();
    final fileKeys = FileKeys(driveDao: db.driveDao);
    final cubit = PublicationLoaderCubit(
      source: PublicationSource(
        pageUri: Uri.parse('https://g.net/PAGE/#/'),
        client: MockClient((request) async {
          final path = request.url.path.replaceFirst('/PAGE/', '');
          final part = parts[path];
          return part == null
              ? http.Response('not found', 404)
              : http.Response.bytes(part, 200);
        }),
      ),
      settingsPath: 'publication.json',
      driveDao: db.driveDao,
      importer: DriveStateImporter(db.driveDao),
      ownerOf: (_) async => owner,
      fileKeys: fileKeys,
      keySession:
          SharedFileKeySession.page(store: SessionKeyValueStore.inMemory({})),
      linkKey: linkKey,
    );
    await cubit.load();
    return (cubit, db, fileKeys);
  }

  test('a drive page opens in the viewer by its link, with its files keys',
      () async {
    final (:posted, :plan) = await publish(scopeRoot: _root);
    final parts = partsOf(posted);
    expect(parts.keys,
        containsAll(['publication.json', 'sealed', 'catalog', 'index.html']));
    expect(
        parts.keys, isNot(anyOf(contains('snapshot'), contains('files.html'))));
    expect(parts.keys, isNot(contains('sitemap.xml')));
    expect(parts.keys, isNot(contains('social.jpg')));

    final (cubit, db, fileKeys) = await open(parts, linkKey: plan.linkKey);
    expect(cubit.state, isA<PublicationReady>(), reason: '${cubit.state}');
    final names = [
      for (final f in await db.select(db.fileEntries).get()) f.name,
    ]..sort();
    expect(names, ['Diary Entry.txt', 'New Name.txt', 'budget-2026.xlsx']);
    for (final MapEntry(:key, :value) in plan.fileKeys.entries) {
      final k =
          await fileKeys.keyFor(driveId: _drive, fileId: key, cipherKey: null);
      expect(b64u(await k!.extractBytes()), value);
    }
    await cubit.close();
    await db.close();
  });

  test('its password opens it, and the owner slot gives the key back',
      () async {
    final (:posted, :plan) =
        await publish(scopeRoot: _root, password: _password);
    final parts = partsOf(posted);
    final (cubit, db, _) = await open(parts);
    expect(cubit.state, isA<PublicationNeedsKey>());
    await cubit.unlock(_password, remember: false);
    expect(cubit.state, isA<PublicationReady>(), reason: '${cubit.state}');
    await cubit.close();
    await db.close();

    final settings = jsonDecode(utf8.decode(parts['publication.json']!))
        as Map<String, dynamic>;
    expect(await ownerPublicationKey(settings, driveKey), plan.publicationKey);
    expect(await ownerPublicationKey(settings, Uint8List(32)), isNull);
  });

  test('nothing public names anything in the drive, or counts its files',
      () async {
    final (:posted, plan: _) =
        await publish(scopeRoot: _root, password: _password);
    for (final item in posted) {
      final tags = _tags(item).values.join('\n');
      final isCiphertext =
          _tags(item)['Content-Type'] == 'application/octet-stream';
      final text = isCiphertext ? '' : utf8.decode(item.data);
      for (final name in _names) {
        expect(tags, isNot(contains(name)), reason: 'a tag names $name');
        expect(text, isNot(contains(name)), reason: 'a file names $name');
        if (isCiphertext) {
          final needle = utf8.encode(name);
          expect(_indexOf(item.data, needle), -1,
              reason: 'ciphertext holds $name in the clear');
        }
      }
    }
    final parts = partsOf(posted);
    final json = utf8.decode(parts['publication.json']!);
    expect(json, isNot(contains('fileCount')));
    expect(json, isNot(contains('rootFolderId')));
    expect(utf8.decode(parts['index.html']!),
        contains('<meta name="robots" content="noindex">'));
    expect(utf8.decode(parts['index.html']!),
        contains('<title>Private page</title>'));
    expect(_tags(posted.last)['Publication-Version'], '3');
  });

  test('a folder page holds its folder only, current and visible', () async {
    final (:posted, :plan) = await publish(scopeRoot: _docs, title: 'Docs');
    expect(plan.fileKeys.keys.toSet(), {_budget, _renamed});
    final (cubit, db, _) = await open(partsOf(posted), linkKey: plan.linkKey);
    expect(cubit.state, isA<PublicationReady>(), reason: '${cubit.state}');
    final folders = await db.select(db.folderEntries).get();
    // The drive's root stands in, nameless, for the folder's parent.
    expect(
      folders.where((f) => f.name.isNotEmpty).map((f) => f.id),
      [_docs],
    );
    // Nothing about the drive around the folder: not even its name.
    final drives = await db.select(db.drives).get();
    expect(drives.single.name, isEmpty);
    expect(await db.select(db.driveRevisions).get(),
        everyElement(isA<DriveRevision>().having((r) => r.name, 'name', '')));
    final files = await db.select(db.fileEntries).get();
    expect(files.map((f) => f.id).toSet(), {_budget, _renamed});
    final revisions = await db.select(db.fileRevisions).get();
    expect(revisions.map((r) => r.name), isNot(contains('Old Name.txt')));
    expect(revisions.where((r) => r.fileId == _renamed), hasLength(1));
    await cubit.close();
    await db.close();
  });

  test('a drive page leaves hidden items out, with their keys', () async {
    final (posted: _, :plan) = await publish(scopeRoot: _root);
    // Nor what is under a ghost folder, nor a file whose latest upload failed
    // or is pending: the owner's summary leaves those out.
    expect(plan.fileKeys.keys.toSet(), {_diary, _budget, _renamed});
    expect(plan.catalog.files.map((f) => f.id).toSet(),
        {_diary, _budget, _renamed});
  });

  test('signing again after the wallet refused never reuses the sealed IV',
      () async {
    final recording = _Recording()..refuseNextSettings = true;
    final (:posted, :plan) =
        await publish(scopeRoot: _root, recording: recording);
    expect(recording.sealedIvs, hasLength(2));
    expect(recording.sealedIvs.toSet(), hasLength(2));
    final parts = partsOf(posted);
    final settings = jsonDecode(utf8.decode(parts['publication.json']!));
    expect(settings['sealed']['iv'], recording.sealedIvs.last);
    final (cubit, db, _) = await open(parts, linkKey: plan.linkKey);
    expect(cubit.state, isA<PublicationReady>(), reason: '${cubit.state}');
    await cubit.close();
    await db.close();
  });

  test('an update carries its slots forward and keeps a password', () async {
    final key = secureRandomBytes(32);
    const id = '7a8b9c0d-1e2f-4a3b-8c4d-5e6f7a8b9c0d';
    final first = await pageSlots(
      publicationKey: key,
      publicationId: id,
      driveKey: driveKey,
      password: _password,
      settings: const Argon2Settings(m: 8192, t: 1, p: 1),
    );
    final next = await pageSlots(
      publicationKey: key,
      publicationId: id,
      driveKey: driveKey,
      previous: first,
      password: 'another one',
    );
    expect(jsonEncode(next), jsonEncode(first));

    final keyOnly = await pageSlots(
        publicationKey: key, publicationId: id, driveKey: driveKey);
    final added = await pageSlots(
      publicationKey: key,
      publicationId: id,
      driveKey: driveKey,
      previous: keyOnly,
      password: _password,
      settings: const Argon2Settings(m: 8192, t: 1, p: 1),
    );
    expect(added.first, keyOnly.first);
    expect(added.map((s) => s['type']), ['owner', 'password']);
  });

  test('a public drive has no catalog', () async {
    await ownerDb.customStatement(
        "UPDATE drives SET privacy = 'public' WHERE id = ?", [_drive]);
    final prepared = await DriveStateCreationService(
      driveDao: ownerDb.driveDao,
      skipSource: _Clean(),
      appVersion: () async => '3.1.0',
    ).prepare(
      driveId: _drive,
      driveKey: null,
      wallet: wallet,
      pageScope: const ArtifactScope(_root),
      catalogKey: SecretKey(secureRandomBytes(32)),
    );
    expect(prepared.isRefused, isTrue);
  });

  test('the cost counts every part of a private page', () async {
    final (:posted, :plan) =
        await publish(scopeRoot: _root, password: _password);
    final publisher = PublicationPublisher(
      uploader: _Recording(),
      driveStateUploader: _NoSnapshots(),
      repository: PublicationRepository(
        graphQLRetry: MockGraphQLRetry(),
        gatewayUrl: () => 'https://turbo-gateway.com',
      ),
      gatewayUrl: () => 'https://turbo-gateway.com',
    );
    final sizes = publisher.itemSizesOf(PublicationJob(
      publicationId: '7a8b9c0d-1e2f-4a3b-8c4d-5e6f7a8b9c0d',
      driveId: _drive,
      rootFolderId: _root,
      scope: const PublicationDriveScope(),
      privacy: 'private',
      owner: owner,
      ownerName: null,
      title: '',
      description: '',
      keywords: const [],
      license: null,
      icon: null,
      cover: null,
      social: null,
      privatePage: plan,
      snapshot: const NoSnapshot(),
      release: release,
      files: const [],
      fileCount: 0,
      labels: const PublicationLabels(
          filesPage: 'a', openPage: 'b', moreFiles: 'c'),
      method: UploadMethod.turbo,
    ));
    expect(sizes, hasLength(posted.length));
    // Each estimate is within the header allowance of what was signed.
    final actual = [for (final item in posted) item.data.length]..sort();
    final estimated = [for (final s in sizes) s - 1100]..sort();
    for (var i = 0; i < actual.length; i++) {
      expect((estimated[i] - actual[i]).abs(), lessThan(64));
    }
  });

  test('a page whose publication.json a viewer would refuse is not priced',
      () async {
    final (posted: _, :plan) = await publish(scopeRoot: _root);
    final publisher = PublicationPublisher(
      uploader: _Recording(),
      driveStateUploader: _NoSnapshots(),
      repository: PublicationRepository(
        graphQLRetry: MockGraphQLRetry(),
        gatewayUrl: () => 'https://turbo-gateway.com',
      ),
      gatewayUrl: () => 'https://turbo-gateway.com',
    );
    PublicationJob job(String description) => PublicationJob(
          publicationId: '7a8b9c0d-1e2f-4a3b-8c4d-5e6f7a8b9c0d',
          driveId: _drive,
          rootFolderId: _root,
          scope: const PublicationDriveScope(),
          privacy: 'private',
          owner: owner,
          ownerName: null,
          title: '',
          description: description,
          keywords: const [],
          license: null,
          icon: null,
          cover: null,
          social: null,
          privatePage: plan,
          snapshot: const NoSnapshot(),
          release: release,
          files: const [],
          fileCount: 0,
          labels: const PublicationLabels(
              filesPage: 'a', openPage: 'b', moreFiles: 'c'),
          method: UploadMethod.turbo,
        );
    // One character to a grapheme counter: an 'a' under 33,000 accents.
    final heavy = 'a${'\u0301' * 33000}';
    expect(
        () => publisher.sizeOf(job(heavy)),
        throwsA(isA<PublicationFailure>()
            .having((e) => e.canRetry, 'canRetry', false)));
    expect(publisher.sizeOf(job('a${'\u0301' * 10}')), greaterThan(0));
  });
}

int _indexOf(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}
