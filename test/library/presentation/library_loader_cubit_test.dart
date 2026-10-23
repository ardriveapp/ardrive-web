import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state/domain/drive_state_outcome.dart';
import 'package:ardrive/drive_state/domain/drive_state_protection.dart';
import 'package:ardrive/library/data/library_source.dart';
import 'package:ardrive/library/domain/library_scope.dart';
import 'package:ardrive/library/presentation/library_loader/library_loader_cubit.dart';
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

/// The `public-gzip` golden fixture, and a `library.json` that publishes it.
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

  Map<String, dynamic> libraryJson({Map<String, dynamic>? scope}) => {
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
        'title': 'Fixture library',
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
    LibraryContents.open = null;
    return db.close();
  });

  LibraryLoaderCubit loader(
    Map<String, Object> files, {
    DriveStateImporter? importer,
    List<Uri>? requests,
  }) =>
      LibraryLoaderCubit(
        source: LibrarySource(
          pageUri: _pageUri,
          client: _gateway(files, requests: requests),
        ),
        settingsPath: 'library.json',
        driveDao: db.driveDao,
        importer: importer ?? DriveStateImporter(db.driveDao),
      );

  group('settings', () {
    blocTest<LibraryLoaderCubit, LibraryLoaderState>(
      'a missing library.json cannot be opened',
      build: () => loader({}),
      act: (cubit) => cubit.load(),
      expect: () => [
        const LibraryLoadingSettings(),
        const LibraryFailed(LibraryFailure.settingsUnreadable),
      ],
    );

    blocTest<LibraryLoaderCubit, LibraryLoaderState>(
      'a damaged library.json cannot be opened',
      build: () => loader({'library.json': '{"version": 1'}),
      act: (cubit) => cubit.load(),
      expect: () => [
        const LibraryLoadingSettings(),
        const LibraryFailed(LibraryFailure.settingsUnreadable),
      ],
    );

    blocTest<LibraryLoaderCubit, LibraryLoaderState>(
      'a newer library.json needs a newer viewer',
      build: () => loader({'library.json': '{"version": 2}'}),
      act: (cubit) => cubit.load(),
      expect: () => [
        const LibraryLoadingSettings(),
        const LibraryFailed(LibraryFailure.needsNewerViewer),
      ],
    );

    blocTest<LibraryLoaderCubit, LibraryLoaderState>(
      'a private library waits for its key and fetches nothing more',
      build: () {
        final private = fixture.libraryJson()
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
        return loader({'library.json': json.encode(private)});
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const LibraryLoadingSettings(),
        isA<LibraryNeedsKey>(),
      ],
      verify: (_) async => expect(await db.driveDao.allDrives().get(), isEmpty),
    );
  });

  group('snapshot', () {
    blocTest<LibraryLoaderCubit, LibraryLoaderState>(
      'a snapshot the gateway does not return can be tried again',
      build: () => loader({'library.json': json.encode(fixture.libraryJson())}),
      act: (cubit) => cubit.load(),
      expect: () => [
        const LibraryLoadingSettings(),
        isA<LibraryLoadingSnapshot>(),
        isA<LibraryFailed>().having(
            (s) => s.failure, 'failure', LibraryFailure.snapshotUnavailable),
      ],
    );

    test('trying again after the gateway catches up opens the library',
        () async {
      final files = <String, Object>{
        'library.json': json.encode(fixture.libraryJson()),
      };
      final cubit = loader(files);
      await cubit.load();
      expect((cubit.state as LibraryFailed).failure,
          LibraryFailure.snapshotUnavailable);

      files['snapshot'] = fixture.body;
      await cubit.retry();

      expect(cubit.state, isA<LibraryReady>());
      await cubit.close();
    });

    blocTest<LibraryLoaderCubit, LibraryLoaderState>(
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
          'library.json': json.encode(fixture.libraryJson()),
          'snapshot': fixture.body,
        }, importer: importer);
      },
      act: (cubit) => cubit.load(),
      skip: 2,
      expect: () => [
        isA<LibraryLoadingSnapshot>(),
        isA<LibraryImporting>(),
        isA<LibraryFailed>().having(
            (s) => s.failure, 'failure', LibraryFailure.snapshotRejected),
      ],
    );

    blocTest<LibraryLoaderCubit, LibraryLoaderState>(
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
          'library.json': json.encode(fixture.libraryJson()),
          'snapshot': fixture.body,
        }, importer: importer);
      },
      act: (cubit) => cubit.load(),
      verify: (cubit) => expect(
        cubit.state,
        isA<LibraryFailed>()
            .having(
                (s) => s.failure, 'failure', LibraryFailure.snapshotUnavailable)
            .having((s) => s.config, 'config', isNotNull),
      ),
    );

    blocTest<LibraryLoaderCubit, LibraryLoaderState>(
      'a folder library whose folder the snapshot lacks cannot be opened',
      build: () => loader({
        'library.json': json.encode(fixture.libraryJson(scope: {
          'type': 'folder',
          'folderId': '00000000-0000-4000-8000-000000000000',
        })),
        'snapshot': fixture.body,
      }),
      act: (cubit) => cubit.load(),
      verify: (cubit) => expect(
        cubit.state,
        isA<LibraryFailed>().having(
            (s) => s.failure, 'failure', LibraryFailure.snapshotRejected),
      ),
    );

    test('hands the importer the owner and tags library.json names', () async {
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
        'library.json': json.encode(fixture.libraryJson()),
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

  group('the public-gzip fixture, end to end', () {
    test('opens as a library with its folders and files', () async {
      final requests = <Uri>[];
      final cubit = loader({
        'library.json': json.encode(fixture.libraryJson()),
        'snapshot': fixture.body,
      }, requests: requests);
      final states = <LibraryLoaderState>[];
      final seen = cubit.stream.listen(states.add);

      await cubit.load();
      await seen.cancel();

      expect(cubit.state, isA<LibraryReady>());
      // What downloads and the info panel prune with.
      expect(LibraryContents.open?.config.driveId, fixture.driveId);
      expect(states.whereType<LibraryLoadingSnapshot>().last.received,
          fixture.body.length);
      expect(states.whereType<LibraryImporting>(), hasLength(1));

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
        'https://sandbox.ardrive.net/PageManifest/library.json',
        'https://sandbox.ardrive.net/PageManifest/snapshot',
      ]);
      await cubit.close();
    });

    test('a folder library opens on a folder the snapshot holds', () async {
      // Read a non-root folder from a first, whole-drive load.
      final probe = loader({
        'library.json': json.encode(fixture.libraryJson()),
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
        'library.json': json.encode(fixture.libraryJson(
          scope: {'type': 'folder', 'folderId': folder.id},
        )),
        'snapshot': fixture.body,
      });
      await cubit.load();

      expect(cubit.state, isA<LibraryReady>());
      expect((cubit.state as LibraryReady).config.scopeRootFolderId, folder.id);
      await cubit.close();
    });
  });
}
