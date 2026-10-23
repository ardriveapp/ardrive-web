import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/library/domain/library_config.dart';
import 'package:ardrive/library/domain/library_mode.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/utils.dart';

const _drive = 'c863be1f-a725-4554-9a9e-18268ed8a035';
const _root = '41520b33-28c1-4892-886b-b845a5709085';
const _a = 'aaaaaaaa-0000-4000-8000-000000000001';
const _b = 'bbbbbbbb-0000-4000-8000-000000000002';
const _c = 'cccccccc-0000-4000-8000-000000000003';

LibraryConfig _config(LibraryScope scope) => LibraryConfig(
      version: 1,
      driveId: _drive,
      rootFolderId: _root,
      scope: scope,
      privacy: 'public',
      owner: 'iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA',
      snapshot: const LibrarySnapshot(path: 'snapshot', txId: 't', tags: {}),
      title: 'Library',
      description: '',
      images: const LibraryImages(),
      publishedAt: null,
      viewer: null,
    );

Future<AppRoutePath> _parse(String location) =>
    AppRouteInformationParser().parseRouteInformation(
      RouteInformation(uri: Uri.parse(location)),
    );

String _restore(AppRoutePath path) =>
    AppRouteInformationParser().restoreRouteInformation(path).uri.toString();

void main() {
  setUp(() => LibraryMode.debugSet('library.json'));
  tearDown(() => LibraryMode.debugSet(null));

  group('library routes', () {
    test('a folder link names the folder and the file', () async {
      final path = await _parse('/folders/$_a?file=f1');

      expect(path.libraryFolderId, _a);
      expect(path.libraryFileId, 'f1');
    });

    for (final location in [
      '/',
      '/sign-in',
      '/get-started',
      '/drives',
      '/drives/$_drive',
      '/drives/$_drive/folders/$_a',
      '/file/abc/view',
      '/view/abc',
      '/folders',
      '/folders/$_a/more',
    ]) {
      test('$location is the library root', () async {
        final path = await _parse(location);

        expect(path.libraryFolderId, isNull);
        expect(path.signingIn, isFalse);
        expect(path.driveId, isNull);
        expect(path.sharedFileId, isNull);
        expect(path.rawTransactionId, isNull);
      });
    }

    test('the address bar shows the root and folders the same way', () {
      expect(_restore(AppRoutePath.library()), '/');
      expect(_restore(AppRoutePath.library(folderId: _a)), '/folders/$_a');
      expect(
        _restore(AppRoutePath.library(folderId: _a, fileId: 'f1')),
        '/folders/$_a?file=f1',
      );
    });
  });

  group('opening a library', () {
    late Database db;
    late AppRouterDelegate router;

    setUp(() async {
      db = getTestDb();
      router = AppRouterDelegate();
      Future<void> folder(String id, String? parent) =>
          db.into(db.folderEntries).insert(FolderEntriesCompanion.insert(
                id: id,
                driveId: _drive,
                name: id,
                parentFolderId: Value(parent),
                path: '',
              ));
      await folder(_root, null);
      await folder(_a, _root);
      await folder(_b, _a);
      await folder(_c, _root);
    });

    tearDown(() => db.close());

    test('opens at the scope root, which is the address bar\'s root', () async {
      await router.openLibrary(
          _config(const LibraryFolderScope(_a)), db.driveDao);

      expect(router.driveId, _drive);
      expect(router.driveFolderId, _a);
      expect(router.currentConfiguration.libraryFolderId, isNull);
    });

    test('a link it arrived with opens its folder when in scope', () async {
      await router.setNewRoutePath(AppRoutePath.library(folderId: _b));
      await router.openLibrary(
          _config(const LibraryFolderScope(_a)), db.driveDao);

      expect(router.driveFolderId, _b);
      expect(router.currentConfiguration.libraryFolderId, _b);
    });

    test('keeps the link it arrived with in the address while it loads',
        () async {
      await router.setNewRoutePath(
          AppRoutePath.library(folderId: _b, fileId: 'f'));

      expect(router.currentConfiguration.libraryFolderId, _b);
      expect(router.currentConfiguration.libraryFileId, 'f');
    });

    test('a link outside a folder library lands on its root', () async {
      await router.setNewRoutePath(AppRoutePath.library(folderId: _c));
      await router.openLibrary(
          _config(const LibraryFolderScope(_a)), db.driveDao);

      expect(router.driveFolderId, _a);
    });

    test('a link followed after opening is checked the same way', () async {
      await router.openLibrary(_config(const LibraryDriveScope()), db.driveDao);

      await router.setNewRoutePath(AppRoutePath.library(folderId: _c));
      expect(router.driveFolderId, _c);

      await router.setNewRoutePath(AppRoutePath.library(folderId: 'nope'));
      expect(router.driveFolderId, _root);
    });

    test('the explorer is anonymous only once the library is open', () async {
      expect(router.canAnonymouslyShowDriveDetail(ProfilePromptAdd()), isFalse);

      await router.openLibrary(_config(const LibraryDriveScope()), db.driveDao);

      expect(router.canAnonymouslyShowDriveDetail(ProfilePromptAdd()), isTrue);
      expect(
        router.canAnonymouslyShowDriveDetail(ProfileCheckingAvailability()),
        isTrue,
      );
    });
  });
}
