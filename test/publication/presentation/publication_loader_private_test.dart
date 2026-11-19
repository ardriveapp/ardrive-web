import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ardrive/core/crypto/file_keys.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/shared_file/shared_file_key_session.dart';
import 'package:ardrive/publication/data/publication_source.dart';
import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/domain/publication_scope.dart';
import 'package:ardrive/publication/domain/sealed/seal_codec.dart';
import 'package:ardrive/publication/domain/sealed/sealing.dart';
import 'package:ardrive/publication/presentation/publication_loader/publication_loader_cubit.dart';
import 'package:ardrive/utils/session_key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../drive_state/conformance/golden_fixtures.dart';
import '../../test_utils/utils.dart';

final _pageUri = Uri.parse('https://sandbox.ardrive.net/PageManifest/#/');

const _publicationId = '7a8b9c0d-1e2f-4a3b-8c4d-5e6f7a8b9c0d';
const _sealedTxId = 'SEALEDtx0000000000000000000000000000000000A';
const _fileId = 'f1e2d3c4-0000-4000-8000-000000000001';
const _password = 'correct horse';

/// The fastest settings a reader runs, so the VM's Argon2id is quick.
const _cheap = Argon2Settings(m: 8192, t: 1, p: 1);

Uint8List _bytes(int length, int seed) =>
    Uint8List.fromList(List.generate(length, (i) => (i * 31 + seed) % 256));

final _publicationKey = _bytes(32, 7);
final _fileKey = _bytes(32, 99);

/// A private page whose catalog is the `private-gzip` golden fixture: a
/// Drive State under the fixture's key, which here is the catalog key.
class _Page {
  _Page._(this.sidecar, this.catalog);

  static Future<_Page> build({
    bool password = true,
    Map<String, Object?>? scope,
  }) async {
    final sidecar = json.decode(
      File('$fixturesPath/private-gzip.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final page = _Page._(
      sidecar,
      File('$fixturesPath/private-gzip.bin').readAsBytesSync(),
    );
    await page._seal(password: password, scope: scope);
    return page;
  }

  final Map<String, dynamic> sidecar;
  final Uint8List catalog;
  late String publicationJson;
  late Uint8List sealed;

  Map<String, dynamic> get _transaction =>
      sidecar['transaction'] as Map<String, dynamic>;
  String get driveId => sidecar['reader']['driveId'] as String;
  String get owner => _transaction['owner'] as String;
  String get catalogTxId => _transaction['id'] as String;

  Map<String, String> get _tags => {
        for (final tag in _transaction['tags'] as List)
          tag['name'] as String: tag['value'] as String,
      };

  Future<void> _seal({
    required bool password,
    Map<String, Object?>? scope,
  }) async {
    final sealing = Sealing();
    final folderId = scope?['folderId'] as String?;
    final slots = <Map<String, Object>>[
      if (password)
        await sealing.passwordSlot(
          password: _password,
          salt: _bytes(16, 3),
          iv: _bytes(12, 4),
          settings: _cheap,
          publicationKey: _publicationKey,
          publicationId: _publicationId,
        ),
      await sealing.ownerSlot(
        driveKey: _bytes(32, 5),
        iv: _bytes(12, 6),
        publicationKey: _publicationKey,
        publicationId: _publicationId,
      ),
    ];
    final sealedIv = _bytes(12, 8);
    publicationJson = buildPrivatePublicationJson(
      publicationId: _publicationId,
      driveId: driveId,
      folderId: folderId,
      owner: owner,
      sealedTxId: _sealedTxId,
      sealedIv: b64u(sealedIv),
      slots: slots,
    );
    final config = jsonDecode(publicationJson) as Map;
    sealed = await sealing.sealBlock(
      _publicationKey,
      sealedIv,
      {
        'v': 1,
        'scope': config['scope'],
        'rootFolderId': fixtureRootFolderId,
        'catalog': {
          'path': 'catalog',
          'txId': catalogTxId,
          'key': b64u(fixtureDriveKey),
          'tags': _tags,
        },
        'files': {_fileId: b64u(_fileKey)},
        'ciphers': <String, Object>{},
      },
      config,
    );
  }

  Map<String, Object> get files => {
        'publication.json': publicationJson,
        'sealed': sealed,
        'catalog': catalog,
      };
}

MockClient _gateway(Map<String, Object> files, {List<String>? requests}) =>
    MockClient((request) async {
      final path = request.url.path.replaceFirst('/PageManifest/', '');
      requests?.add(path);
      final file = files[path];
      if (file == null) return http.Response('not found', 404);
      return file is String
          ? http.Response(file, 200)
          : http.Response.bytes(file as List<int>, 200);
    });

/// An Argon2id that never finishes its work.
class _BrokenArgon2id implements Argon2idKdf {
  @override
  Future<Uint8List> derive({
    required List<int> password,
    required List<int> salt,
    required Argon2Settings settings,
  }) async =>
      throw StateError('out of memory');
}

void main() {
  late Database db;
  late FileKeys fileKeys;
  late Map<String, String> tab;

  setUp(() {
    db = getTestDb();
    fileKeys = FileKeys(driveDao: db.driveDao);
    tab = {};
  });

  tearDown(() {
    PublicationContents.open = null;
    return db.close();
  });

  PublicationLoaderCubit loader(
    _Page page, {
    String? linkKey,
    Future<String?> Function(String txId)? ownerOf,
    Sealing? sealing,
    List<String>? requests,
    Map<String, Object>? files,
  }) =>
      PublicationLoaderCubit(
        source: PublicationSource(
          pageUri: _pageUri,
          client: _gateway(files ?? page.files, requests: requests),
        ),
        settingsPath: 'publication.json',
        driveDao: db.driveDao,
        importer: DriveStateImporter(db.driveDao),
        ownerOf: ownerOf ?? (_) async => page.owner,
        fileKeys: fileKeys,
        sealing: sealing,
        keySession: SharedFileKeySession.page(
          store: SessionKeyValueStore.inMemory(tab),
        ),
        linkKey: linkKey,
      );

  Future<void> expectOpened(PublicationLoaderCubit cubit, _Page page) async {
    final state = cubit.state;
    expect(state, isA<PublicationReady>(), reason: '$state');
    state as PublicationReady;
    expect(state.config.rootFolderId, fixtureRootFolderId);
    expect(state.config.isSealed, isTrue);
    final key = await fileKeys.keyFor(
      driveId: page.driveId,
      fileId: _fileId,
      cipherKey: null,
    );
    expect(await key!.extractBytes(), _fileKey);
    final drive =
        await db.driveDao.driveById(driveId: page.driveId).getSingle();
    expect(drive.importedArtifactTxId, page.catalogTxId);
  }

  test('a key in the link opens it, without the unlock screen', () async {
    final page = await _Page.build();
    final cubit = loader(page, linkKey: b64u(_publicationKey));
    final states = <PublicationLoaderState>[];
    final sub = cubit.stream.listen(states.add);
    await cubit.load();
    await expectOpened(cubit, page);
    expect(states.whereType<PublicationNeedsKey>(), isEmpty);
    expect((cubit.state as PublicationReady).keyRemembered, isFalse);
    expect(tab, isEmpty);
    await sub.cancel();
    await cubit.close();
  });

  test('without a key it waits on the unlock screen, and reads no catalog',
      () async {
    final page = await _Page.build();
    final requests = <String>[];
    final cubit = loader(page, requests: requests);
    await cubit.load();
    expect(
      cubit.state,
      isA<PublicationNeedsKey>()
          .having((s) => s.hasPassword, 'hasPassword', isTrue)
          .having((s) => s.error, 'error', isNull),
    );
    expect(requests, ['publication.json', 'sealed']);
    expect(await db.driveDao.allDrives().get(), isEmpty);
    await cubit.close();
  });

  test('a page without a password says so', () async {
    final page = await _Page.build(password: false);
    final cubit = loader(page);
    await cubit.load();
    expect((cubit.state as PublicationNeedsKey).hasPassword, isFalse);
    await cubit.close();
  });

  test('the password opens it, and Remember keeps the key, not the password',
      () async {
    final page = await _Page.build();
    final cubit = loader(page);
    await cubit.load();
    await cubit.unlock(_password, remember: true);
    await expectOpened(cubit, page);
    expect((cubit.state as PublicationReady).keyRemembered, isTrue);
    expect(tab, {'publicationKey.$_publicationId': b64u(_publicationKey)});
    await cubit.close();
  });

  test('a pasted key opens it, and nothing is kept without Remember', () async {
    final page = await _Page.build();
    final cubit = loader(page);
    await cubit.load();
    await cubit.unlock(b64u(_publicationKey), remember: false);
    await expectOpened(cubit, page);
    expect(tab, isEmpty);
    await cubit.close();
  });

  test('a wrong password stays on the unlock screen and says so', () async {
    final page = await _Page.build();
    final cubit = loader(page);
    await cubit.load();
    final states = <PublicationLoaderState>[];
    final sub = cubit.stream.listen(states.add);
    await cubit.unlock('wrong', remember: true);
    expect(
        states.first,
        isA<PublicationNeedsKey>()
            .having((s) => s.isChecking, 'isChecking', isTrue));
    expect(
      cubit.state,
      isA<PublicationNeedsKey>()
          .having((s) => s.error, 'error', PublicationUnlockError.didntOpen)
          .having((s) => s.isChecking, 'isChecking', isFalse),
    );
    expect(tab, isEmpty);
    // It can still be opened afterwards.
    await cubit.unlock(_password, remember: false);
    await expectOpened(cubit, page);
    await sub.cancel();
    await cubit.close();
  });

  test('a link whose key does not open it lands on the unlock screen',
      () async {
    final page = await _Page.build();
    final cubit = loader(page, linkKey: b64u(_bytes(32, 200)));
    await cubit.load();
    expect(
      cubit.state,
      isA<PublicationNeedsKey>().having(
          (s) => s.error, 'error', PublicationUnlockError.linkKeyDidntOpen),
    );
    await cubit.close();
  });

  test('a malformed key in the link is passed over', () async {
    final page = await _Page.build();
    final cubit = loader(page, linkKey: 'not-a-key');
    await cubit.load();
    expect(cubit.state, isA<PublicationNeedsKey>());
    await cubit.close();
  });

  test('a key this tab remembers opens it', () async {
    final page = await _Page.build();
    tab['publicationKey.$_publicationId'] = b64u(_publicationKey);
    final cubit = loader(page);
    await cubit.load();
    await expectOpened(cubit, page);
    expect((cubit.state as PublicationReady).keyRemembered, isTrue);
    await cubit.close();
  });

  test('a remembered key that no longer opens it is forgotten', () async {
    final page = await _Page.build();
    tab['publicationKey.$_publicationId'] = b64u(_bytes(32, 201));
    final cubit = loader(page);
    await cubit.load();
    expect(
      cubit.state,
      isA<PublicationNeedsKey>().having((s) => s.error, 'error', isNull),
    );
    expect(tab, isEmpty);
    await cubit.close();
  });

  test('Lock forgets the remembered key', () async {
    final page = await _Page.build();
    tab['publicationKey.$_publicationId'] = b64u(_publicationKey);
    final cubit = loader(page);
    await cubit.load();
    await cubit.forgetKey();
    expect(tab, isEmpty);
    expect((cubit.state as PublicationReady).keyRemembered, isFalse);
    await cubit.close();
  });

  test('Argon2id failing is not a wrong password', () async {
    final page = await _Page.build();
    final cubit = loader(page, sealing: Sealing(argon2id: _BrokenArgon2id()));
    await cubit.load();
    await cubit.unlock(_password, remember: false);
    expect(
      cubit.state,
      isA<PublicationNeedsKey>().having(
          (s) => s.error, 'error', PublicationUnlockError.passwordNotChecked),
    );
    await cubit.close();
  });

  test('a sealed block someone else signed is refused before it is read',
      () async {
    final page = await _Page.build();
    final requests = <String>[];
    final cubit = loader(
      page,
      linkKey: b64u(_publicationKey),
      requests: requests,
      ownerOf: (txId) async =>
          txId == _sealedTxId ? 'someone-else' : page.owner,
    );
    await cubit.load();
    expect(
      cubit.state,
      const PublicationFailed(PublicationFailure.snapshotRejected),
    );
    expect(requests, ['publication.json']);
    await cubit.close();
  });

  test('a catalog someone else signed is refused', () async {
    final page = await _Page.build();
    final cubit = loader(
      page,
      linkKey: b64u(_publicationKey),
      ownerOf: (txId) async =>
          txId == page.catalogTxId ? 'someone-else' : page.owner,
    );
    await cubit.load();
    expect(
      cubit.state,
      const PublicationFailed(PublicationFailure.snapshotRejected),
    );
    await cubit.close();
  });

  test('a folder page whose folder the catalog lacks is refused', () async {
    final page = await _Page.build(
      scope: {
        'type': 'folder',
        'folderId': '00000000-0000-4000-8000-0000000000aa'
      },
    );
    final cubit = loader(page, linkKey: b64u(_publicationKey));
    await cubit.load();
    expect(
      cubit.state,
      const PublicationFailed(PublicationFailure.snapshotRejected),
    );
    await cubit.close();
  });

  test('a catalog the gateway does not return can be tried again', () async {
    final page = await _Page.build();
    final files = Map.of(page.files)..remove('catalog');
    final cubit = loader(page, linkKey: b64u(_publicationKey), files: files);
    await cubit.load();
    expect(
      cubit.state,
      isA<PublicationFailed>().having(
          (s) => s.failure, 'failure', PublicationFailure.snapshotUnavailable),
    );
    files['catalog'] = page.catalog;
    await cubit.retry();
    await expectOpened(cubit, page);
    await cubit.close();
  });

  test('a sealed part over the limit is never read whole', () async {
    final page = await _Page.build();
    final cubit = loader(
      page,
      linkKey: b64u(_publicationKey),
      files: {...page.files, 'sealed': Uint8List(maxSealedBytes + 1)},
    );
    await cubit.load();
    expect(cubit.state, isA<PublicationFailed>());
    await cubit.close();
  });

  test('the old private snapshot form is refused, not left waiting', () async {
    final page = await _Page.build();
    final cubit = loader(page, files: {
      'publication.json': json.encode({
        'version': 1,
        'driveId': page.driveId,
        'rootFolderId': fixtureRootFolderId,
        'scope': {'type': 'drive'},
        'privacy': 'private',
        'owner': page.owner,
        'snapshot': {
          'path': 'snapshot',
          'txId': page.catalogTxId,
          'tags': {'Cipher': 'AES256-GCM', 'Cipher-IV': 'aXY'},
        },
        'title': 'Old',
      }),
    });
    await cubit.load();
    expect(
      cubit.state,
      const PublicationFailed(PublicationFailure.settingsUnreadable),
    );
    await cubit.close();
  });

  group('publicationLinkKey', () {
    test('reads k from the route in the fragment', () {
      expect(
        publicationLinkKey(Uri.parse('https://g.net/TX/#/?k=abc')),
        'abc',
      );
      expect(
        publicationLinkKey(
            Uri.parse('https://g.net/TX/#/folders/f?file=x&k=abc')),
        'abc',
      );
    });

    test('is null without one', () {
      expect(publicationLinkKey(Uri.parse('https://g.net/TX/#/')), isNull);
      expect(publicationLinkKey(Uri.parse('https://g.net/TX/#/?k=')), isNull);
      expect(publicationLinkKey(Uri.parse('https://g.net/TX/')), isNull);
    });

    test('never reads the query the server sees', () {
      expect(
          publicationLinkKey(Uri.parse('https://g.net/TX/?k=abc#/')), isNull);
    });
  });

  test('the parsed config of a private page', () async {
    final page = await _Page.build();
    final config = PublicationConfig.parse(page.publicationJson);
    expect(config.isSealed, isTrue);
    expect(config.rootFolderId, isEmpty);
    expect(config.title, isEmpty);
    expect(config.scope, const PublicationDriveScope());
    expect(config.sealed!.publicationId, _publicationId);
    expect(config.sealed!.txId, _sealedTxId);
    expect(config.opened(rootFolderId: fixtureRootFolderId).rootFolderId,
        fixtureRootFolderId);
  });
}
