import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state/domain/drive_state_outcome.dart';
import 'package:ardrive/drive_state/domain/drive_state_protection.dart';
import 'package:ardrive/publication/data/publication_source.dart';
import 'package:ardrive/publication/domain/publication_scope.dart';
import 'package:ardrive/publication/presentation/publication_loader/publication_loader_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

import '../../drive_state/conformance/golden_fixtures.dart';
import '../../test_utils/utils.dart';

class _MockImporter extends Mock implements DriveStateImporter {}

class _FakeCandidate extends Fake implements DriveStateArtifactCandidate {}

final _pageUri = Uri.parse('https://sandbox.ardrive.net/PageManifest/#/');

/// The `public-gzip` golden fixture, and a `publication.json` that publishes it.
class _Fixture {
  _Fixture._(this.sidecar, this.body);

  factory _Fixture.load() {
    final sidecar = json.decode(
      File('$fixturesPath/public-gzip.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final body = File('$fixturesPath/public-gzip.bin').readAsBytesSync();
    return _Fixture._(sidecar, body);
  }

  final Map<String, dynamic> sidecar;
  final Uint8List body;

  Map<String, dynamic> get _reader => sidecar['reader'] as Map<String, dynamic>;
  Map<String, dynamic> get _transaction =>
      sidecar['transaction'] as Map<String, dynamic>;

  String get driveId => _reader['driveId'] as String;
  String get owner => _reader['ownerAddress'] as String;

  Map<String, String> get tags => {
        for (final tag in _transaction['tags'] as List)
          tag['name'] as String: tag['value'] as String,
      };

  Map<String, dynamic> publicationJson({Map<String, dynamic>? scope}) => {
        'version': 1,
        'driveId': driveId,
        'rootFolderId': fixtureRootFolderId,
        'scope': scope ?? {'type': 'drive'},
        'privacy': 'public',
        'owner': owner,
        'snapshot': {
          'path': 'snapshot',
          'txId': _transaction['id'],
          'tags': tags,
        },
        'title': 'Fixture publication',
      };
}

/// A gateway serving a page's files from [files], by path; anything else 404s.
MockClient _gateway(Map<String, Object> files, {List<Uri>? requests}) =>
    MockClient((request) async {
      requests?.add(request.url);
      final path = request.url.path.replaceFirst('/PageManifest/', '');
      final file = files[path];
      if (file == null) return http.Response('not found', 404);
      return file is String
          ? http.Response(file, 200)
          : http.Response.bytes(file as List<int>, 200);
    });

void main() {
  late Database db;
  late _Fixture fixture;

  setUpAll(() {
    registerFallbackValue(_FakeCandidate());
    registerFallbackValue(
      DriveStateProtection.forDrive(privacy: 'public', driveKey: null)
          .protection!,
    );
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    db = getTestDb();
    fixture = _Fixture.load();
  });

  tearDown(() {
    PublicationContents.open = null;
    return db.close();
  });

  PublicationLoaderCubit loader(
    Map<String, Object> files, {
    DriveStateImporter? importer,
    List<Uri>? requests,
    Future<String?> Function(String txId)? ownerOf,
  }) =>
      PublicationLoaderCubit(
        source: PublicationSource(
          pageUri: _pageUri,
          client: _gateway(files, requests: requests),
        ),
        settingsPath: 'publication.json',
        driveDao: db.driveDao,
        importer: importer ?? DriveStateImporter(db.driveDao),
        // The gateway confirms the owner publication.json names.
        ownerOf: ownerOf ?? (_) async => fixture.owner,
      );

  group('a file page', () {
    const metadataTx = 'FILEmeta00000000000000000000000000000000000';
    String page() => json.encode({
          'version': 2,
          'driveId': fixture.driveId,
          'rootFolderId': fixtureRootFolderId,
          'scope': {
            'type': 'file',
            'fileId': 'f1e2d3c4-0000-4000-8000-000000000001',
          },
          'privacy': 'public',
          'owner': fixture.owner,
          'file': {
            'dataTxId': 'FILEdata00000000000000000000000000000000000',
            'metadataTxId': metadataTx,
            'name': 'Lake.jpg',
          },
          'title': 'A lake',
        });

    test('opens once its file is signed by its owner, with nothing to import',
        () async {
      final asked = <String>[];
      final importer = _MockImporter();
      final requests = <Uri>[];
      final cubit = loader(
        {'publication.json': page()},
        importer: importer,
        requests: requests,
        ownerOf: (txId) async {
          asked.add(txId);
          return fixture.owner;
        },
      );
      await cubit.load();
      final state = cubit.state;
      expect(state, isA<PublicationReady>());
      expect((state as PublicationReady).ownerVerified, isTrue);
      expect(state.stats, isNull);
      expect(asked, [metadataTx]);
      expect(
          requests.map((u) => u.path), isNot(contains(endsWith('/snapshot'))));
      verifyNever(() => importer.import(
            candidate: any(named: 'candidate'),
            body: any(named: 'body'),
            protection: any(named: 'protection'),
            expectedOwnerAddress: any(named: 'expectedOwnerAddress'),
          ));
      expect(PublicationContents.open, isNull);
      await cubit.close();
    });

    PublicationLoaderCubit withFacts(Map<String, String> tags,
            {String? owner}) =>
        PublicationLoaderCubit(
          source: PublicationSource(
            pageUri: _pageUri,
            client: _gateway({'publication.json': page()}),
          ),
          settingsPath: 'publication.json',
          driveDao: db.driveDao,
          importer: DriveStateImporter(db.driveDao),
          ownerOf: (_) async => fixture.owner,
          factsOf: (_) async => (owner: owner ?? fixture.owner, tags: tags),
        );
    Map<String, String> fileTags({String? fileId, String? driveId}) => {
          'Entity-Type': 'file',
          'File-Id': fileId ?? 'f1e2d3c4-0000-4000-8000-000000000001',
          'Drive-Id': driveId ?? fixture.driveId,
        };

    test('opens when its metadata is its own file\'s', () async {
      final cubit = withFacts(fileTags());
      await cubit.load();
      expect((cubit.state as PublicationReady).ownerVerified, isTrue);
      await cubit.close();
    });

    test('is refused when the owner\'s metadata is another file\'s', () async {
      for (final tags in [
        fileTags(fileId: 'aaaaaaaa-0000-4000-8000-00000000000a'),
        fileTags(driveId: 'another-drive'),
        {...fileTags(), 'Entity-Type': 'folder'},
      ]) {
        final cubit = withFacts(tags);
        await cubit.load();
        expect(cubit.state,
            const PublicationFailed(PublicationFailure.snapshotRejected),
            reason: '$tags');
        await cubit.close();
      }
    });

    test('is refused when someone else signed its file', () async {
      final cubit = loader(
        {'publication.json': page()},
        ownerOf: (_) async => 'someoneElse0000000000000000000000000000000',
      );
      await cubit.load();
      expect(cubit.state,
          const PublicationFailed(PublicationFailure.snapshotRejected));
      await cubit.close();
    });

    test('opens as declared when the gateway cannot say who signed it',
        () async {
      final cubit =
          loader({'publication.json': page()}, ownerOf: (_) async => null);
      await cubit.load();
      expect((cubit.state as PublicationReady).ownerVerified, isFalse);
      await cubit.close();
    });
  });

  group('settings', () {
    blocTest<PublicationLoaderCubit, PublicationLoaderState>(
      'a missing publication.json cannot be opened',
      build: () => loader({}),
      act: (cubit) => cubit.load(),
      expect: () => [
        const PublicationLoadingSettings(),
        const PublicationFailed(PublicationFailure.settingsUnreadable),
      ],
    );

    blocTest<PublicationLoaderCubit, PublicationLoaderState>(
      'a damaged publication.json cannot be opened',
      build: () => loader({'publication.json': '{"version": 1'}),
      act: (cubit) => cubit.load(),
      expect: () => [
        const PublicationLoadingSettings(),
        const PublicationFailed(PublicationFailure.settingsUnreadable),
      ],
    );

    blocTest<PublicationLoaderCubit, PublicationLoaderState>(
      'a newer publication.json needs a newer viewer',
      build: () => loader({'publication.json': '{"version": 3}'}),
      act: (cubit) => cubit.load(),
      expect: () => [
        const PublicationLoadingSettings(),
        const PublicationFailed(PublicationFailure.needsNewerViewer),
      ],
    );

    blocTest<PublicationLoaderCubit, PublicationLoaderState>(
      'a private publication waits for its key and fetches nothing more',
      build: () {
        final private = fixture.publicationJson()
          ..['privacy'] = 'private'
          ..['snapshot'] = {
            'path': 'snapshot',
            'txId': fixture.sidecar['transaction']['id'],
            'tags': {
              ...fixture.tags,
              'Cipher': 'AES256-GCM',
              'Cipher-IV': 'aXY'
            },
          };
        return loader({'publication.json': json.encode(private)});
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const PublicationLoadingSettings(),
        isA<PublicationNeedsKey>(),
      ],
      verify: (_) async => expect(await db.driveDao.allDrives().get(), isEmpty),
    );
  });

  group('snapshot', () {
    blocTest<PublicationLoaderCubit, PublicationLoaderState>(
      'a snapshot the gateway does not return can be tried again',
      build: () =>
          loader({'publication.json': json.encode(fixture.publicationJson())}),
      act: (cubit) => cubit.load(),
      expect: () => [
        const PublicationLoadingSettings(),
        isA<PublicationLoadingSnapshot>(),
        isA<PublicationFailed>().having((s) => s.failure, 'failure',
            PublicationFailure.snapshotUnavailable),
      ],
    );

    test('trying again after the gateway catches up opens the publication',
        () async {
      final files = <String, Object>{
        'publication.json': json.encode(fixture.publicationJson()),
      };
      final cubit = loader(files);
      await cubit.load();
      expect((cubit.state as PublicationFailed).failure,
          PublicationFailure.snapshotUnavailable);

      files['snapshot'] = fixture.body;
      await cubit.retry();

      expect(cubit.state, isA<PublicationReady>());
      await cubit.close();
    });

    blocTest<PublicationLoaderCubit, PublicationLoaderState>(
      'a snapshot the importer rejects cannot be opened',
      build: () {
        final importer = _MockImporter();
        when(() => importer.import(
              candidate: any(named: 'candidate'),
              body: any(named: 'body'),
              protection: any(named: 'protection'),
              expectedOwnerAddress: any(named: 'expectedOwnerAddress'),
            )).thenAnswer((_) async => const DriveStateImportResult.rejected(
              DriveStateOutcome.ownerMismatch,
              'uploaded by someone else',
            ));
        return loader({
          'publication.json': json.encode(fixture.publicationJson()),
          'snapshot': fixture.body,
        }, importer: importer);
      },
      act: (cubit) => cubit.load(),
      skip: 2,
      expect: () => [
        isA<PublicationLoadingSnapshot>(),
        isA<PublicationImporting>(),
        // A refused page shows nothing of its own settings.
        const PublicationFailed(PublicationFailure.snapshotRejected),
      ],
    );

    blocTest<PublicationLoaderCubit, PublicationLoaderState>(
      'an unexpected error ends on the retryable screen, not on loading',
      build: () {
        final importer = _MockImporter();
        when(() => importer.import(
              candidate: any(named: 'candidate'),
              body: any(named: 'body'),
              protection: any(named: 'protection'),
              expectedOwnerAddress: any(named: 'expectedOwnerAddress'),
            )).thenThrow(StateError('sqlite3.wasm did not load'));
        return loader({
          'publication.json': json.encode(fixture.publicationJson()),
          'snapshot': fixture.body,
        }, importer: importer);
      },
      act: (cubit) => cubit.load(),
      verify: (cubit) => expect(
        cubit.state,
        isA<PublicationFailed>()
            .having((s) => s.failure, 'failure',
                PublicationFailure.snapshotUnavailable)
            .having((s) => s.config, 'config', isNotNull),
      ),
    );

    blocTest<PublicationLoaderCubit, PublicationLoaderState>(
      'a folder publication whose folder the snapshot lacks cannot be opened',
      build: () => loader({
        'publication.json': json.encode(fixture.publicationJson(scope: {
          'type': 'folder',
          'folderId': '00000000-0000-4000-8000-000000000000',
        })),
        'snapshot': fixture.body,
      }),
      act: (cubit) => cubit.load(),
      verify: (cubit) => expect(
        cubit.state,
        isA<PublicationFailed>().having(
            (s) => s.failure, 'failure', PublicationFailure.snapshotRejected),
      ),
    );

    test('hands the importer the owner and tags publication.json names',
        () async {
      final importer = _MockImporter();
      when(() => importer.import(
            candidate: any(named: 'candidate'),
            body: any(named: 'body'),
            protection: any(named: 'protection'),
            expectedOwnerAddress: any(named: 'expectedOwnerAddress'),
          )).thenAnswer((_) async => const DriveStateImportResult.rejected(
            DriveStateOutcome.integrityFailed,
            'stop here',
          ));
      final cubit = loader({
        'publication.json': json.encode(fixture.publicationJson()),
        'snapshot': fixture.body,
      }, importer: importer);

      await cubit.load();

      final call = verify(() => importer.import(
            candidate: captureAny(named: 'candidate'),
            body: captureAny(named: 'body'),
            protection: any(named: 'protection'),
            expectedOwnerAddress: captureAny(named: 'expectedOwnerAddress'),
          ))
        ..called(1);
      final candidate = call.captured[0] as DriveStateArtifactCandidate;
      expect(candidate.txId, fixture.sidecar['transaction']['id']);
      expect(candidate.ownerAddress, fixture.owner);
      expect(candidate.tags, fixture.tags);
      expect(call.captured[1], fixture.body);
      expect(call.captured[2], fixture.owner);
      await cubit.close();
    });
  });

  group('the owner', () {
    const stranger = 'STRANGER_ADDRESS_000000000000000000000000000';

    Map<String, Object> page(Map<String, dynamic> config) => {
          'publication.json': json.encode(config),
          'snapshot': fixture.body,
        };

    test('a snapshot signed by someone else is refused before it is fetched',
        () async {
      final requests = <Uri>[];
      final asked = <String>[];
      final cubit = loader(
        page(fixture.publicationJson()
          ..['title'] = 'Official ArDrive downloads'
          ..['ownerName'] = 'ArDrive'),
        requests: requests,
        ownerOf: (txId) async {
          asked.add(txId);
          return stranger;
        },
      );
      final states = <PublicationLoaderState>[];
      final seen = cubit.stream.listen(states.add);
      await cubit.load();
      await pumpEventQueue();
      await seen.cancel();
      // The generic refusal: nothing the refused page says about itself, so
      // no title, icon or display name reaches the screen.
      expect(cubit.state,
          const PublicationFailed(PublicationFailure.snapshotRejected));
      expect(states, [
        const PublicationLoadingSettings(),
        const PublicationFailed(PublicationFailure.snapshotRejected),
      ]);
      expect(asked, [fixture.sidecar['transaction']['id']],
          reason: 'one lookup, of the snapshot');
      expect(
          requests.map((u) => u.path), isNot(contains(endsWith('snapshot'))));
      await cubit.close();
    });

    test('a confirmed owner is named', () async {
      final cubit =
          loader(page(fixture.publicationJson()..['ownerName'] = 'Phil'));
      await cubit.load();
      final ready = cubit.state as PublicationReady;
      expect(ready.ownerVerified, isTrue);
      expect(ready.config.ownerName, 'Phil');
      await cubit.close();
    });

    test('an owner the gateway cannot confirm opens the page as declared',
        () async {
      // A new snapshot is not indexed until its bundle is mined, which is
      // when its owner first opens the page.
      for (final ownerOf in <Future<String?> Function(String)>[
        (_) async => null,
        (_) async => throw Exception('GraphQL is down'),
      ]) {
        final cubit = loader(
            page(fixture.publicationJson()..['ownerName'] = 'Phil'),
            ownerOf: ownerOf);
        await cubit.load();
        final ready = cubit.state as PublicationReady;
        expect(ready.ownerVerified, isFalse);
        expect(ready.config.ownerName, 'Phil');
        expect(ready.config.owner, fixture.owner);
        await cubit.close();
      }
    });

    test('a display name is shown as the owner wrote it', () async {
      // Self-declared: the verified address beside it is the identity.
      final cubit = loader(
          page(fixture.publicationJson()..['ownerName'] = 'ArDrive Support'));
      await cubit.load();
      final ready = cubit.state as PublicationReady;
      expect(ready.ownerVerified, isTrue);
      expect(ready.config.ownerName, 'ArDrive Support');
      expect(ready.config.owner, fixture.owner);
      await cubit.close();
    });

    test('a title may say ArDrive', () async {
      final cubit = loader(page(fixture.publicationJson()
        ..['title'] = 'ArDrive Photos Drive'
        ..['ownerName'] = 'Phil'));
      await cubit.load();
      final ready = cubit.state as PublicationReady;
      expect(ready.config.title, 'ArDrive Photos Drive');
      expect(ready.config.ownerName, 'Phil');
      await cubit.close();
    });
  });

  group('the public-gzip fixture, end to end', () {
    test('opens as a publication with its folders and files', () async {
      final requests = <Uri>[];
      final cubit = loader({
        'publication.json': json.encode(fixture.publicationJson()),
        'snapshot': fixture.body,
      }, requests: requests);
      final states = <PublicationLoaderState>[];
      final seen = cubit.stream.listen(states.add);

      await cubit.load();
      await seen.cancel();

      expect(cubit.state, isA<PublicationReady>());
      // What downloads and the info panel prune with.
      expect(PublicationContents.open?.config.driveId, fixture.driveId);
      expect(states.whereType<PublicationLoadingSnapshot>().last.received,
          fixture.body.length);
      expect(states.whereType<PublicationImporting>(), hasLength(1));

      final drive =
          await db.driveDao.driveById(driveId: fixture.driveId).getSingle();
      expect(drive.ownerAddress, fixture.owner);
      expect(drive.privacy, 'public');

      final folders = await (db.select(db.folderEntries)
            ..where((f) => f.driveId.equals(fixture.driveId)))
          .get();
      final files = await (db.select(db.fileEntries)
            ..where((f) => f.driveId.equals(fixture.driveId)))
          .get();
      expect(folders, hasLength(3));
      expect(files, hasLength(5));
      expect(folders.map((f) => f.id), contains(fixtureRootFolderId));

      // Only the page's own two files, both beside the page.
      expect(requests.map((u) => u.toString()), [
        'https://sandbox.ardrive.net/PageManifest/publication.json',
        'https://sandbox.ardrive.net/PageManifest/snapshot',
      ]);
      await cubit.close();
    });

    test('a folder publication opens on a folder the snapshot holds', () async {
      // Read a non-root folder from a first, whole-drive load.
      final probe = loader({
        'publication.json': json.encode(fixture.publicationJson()),
        'snapshot': fixture.body,
      });
      await probe.load();
      final folder = (await (db.select(db.folderEntries)
                ..where((f) => f.driveId.equals(fixture.driveId)))
              .get())
          .firstWhere((f) => f.id != fixtureRootFolderId);
      await probe.close();
      await db.close();
      db = getTestDb();

      final cubit = loader({
        'publication.json': json.encode(fixture.publicationJson(
          scope: {'type': 'folder', 'folderId': folder.id},
        )),
        'snapshot': fixture.body,
      });
      await cubit.load();

      expect(cubit.state, isA<PublicationReady>());
      expect((cubit.state as PublicationReady).config.scopeRootFolderId,
          folder.id);
      await cubit.close();
    });
  });
}
