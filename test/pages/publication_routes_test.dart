import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
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

PublicationConfig _config(PublicationScope scope) => PublicationConfig(
      version: 1,
      driveId: _drive,
      rootFolderId: _root,
      scope: scope,
      privacy: 'public',
      owner: 'iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA',
      snapshot:
          const PublicationSnapshot(path: 'snapshot', txId: 't', tags: {}),
      title: 'Publication',
      description: '',
      images: const PublicationImages(),
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
  setUp(() => PublicationMode.debugSet('publication.json'));
  tearDown(() => PublicationMode.debugSet(null));

  group('publication routes', () {
    test('a folder link names the folder and the file', () async {
      final path = await _parse('/folders/$_a?file=f1');

      expect(path.publicationFolderId, _a);
      expect(path.publicationFileId, 'f1');
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
      test('$location is the publication root', () async {
        final path = await _parse(location);

        expect(path.publicationFolderId, isNull);
        expect(path.signingIn, isFalse);
        expect(path.driveId, isNull);
        expect(path.sharedFileId, isNull);
        expect(path.rawTransactionId, isNull);
      });
    }

    test('the address bar shows the root and folders the same way', () {
      expect(_restore(AppRoutePath.publication()), '/');
      expect(_restore(AppRoutePath.publication(folderId: _a)), '/folders/$_a');
      expect(
        _restore(AppRoutePath.publication(folderId: _a, fileId: 'f1')),
        '/folders/$_a?file=f1',
      );
    });
  });

  group('a file page', () {
    // Canonical base64url: the last character's spare bits are zero.
    final key = '${'K' * 42}A';
    const fileId = 'f1e2d3c4-0000-4000-8000-000000000001';

    PublicationConfig filePage() => const PublicationConfig(
          version: 2,
          driveId: _drive,
          rootFolderId: _root,
          scope: PublicationFileScope(fileId),
          privacy: 'private',
          owner: 'iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA',
          snapshot: null,
          file: PublicationFile(
            dataTxId: 'FILEdata00000000000000000000000000000000000',
            metadataTxId: 'FILEmeta00000000000000000000000000000000000',
            cipher: 'AES256-GCM',
            cipherIv: 'aXZpdml2aXZpdml2',
          ),
          title: 'Plans',
          description: '',
          images: PublicationImages(),
          publishedAt: null,
          viewer: null,
        );

    test('reads the key from the hash route', () async {
      final path = await _parse('/?k=$key');

      expect(path.sharedRawFileKey, key);
      expect(path.sharedFileKey, isNotNull);
      expect(path.publicationFolderId, isNull);
    });

    test('keeps the key in the address through the first report, and after',
        () async {
      final db = getTestDb();
      addTearDown(db.close);
      final router = AppRouterDelegate();
      await router.setNewRoutePath(await _parse('/?k=$key'));

      expect(_restore(router.currentConfiguration), '/?k=$key');

      await router.openPublication(filePage(), db.driveDao);

      expect(router.sharedFileId, fileId);
      expect(router.sharedFileKey, isNotNull);
      expect(router.sharedFileLinkPayload?.cipher, 'AES256-GCM');
      expect(router.sharedFileLinkPayload?.isPinned, isTrue);
      expect(router.driveId, isNull);
      expect(_restore(router.currentConfiguration), '/?k=$key');
    });

    test('without a key it opens locked, and the address stays the root',
        () async {
      final db = getTestDb();
      addTearDown(db.close);
      final router = AppRouterDelegate();
      await router.setNewRoutePath(await _parse('/'));
      await router.openPublication(filePage(), db.driveDao);

      expect(router.sharedFileId, fileId);
      expect(router.sharedFileKey, isNull);
      expect(_restore(router.currentConfiguration), '/');
    });
  });

  group('opening a publication', () {
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
      await router.openPublication(
          _config(const PublicationFolderScope(_a)), db.driveDao);

      expect(router.driveId, _drive);
      expect(router.driveFolderId, _a);
      expect(router.currentConfiguration.publicationFolderId, isNull);
    });

    test('a link it arrived with opens its folder when in scope', () async {
      await router.setNewRoutePath(AppRoutePath.publication(folderId: _b));
      await router.openPublication(
          _config(const PublicationFolderScope(_a)), db.driveDao);

      expect(router.driveFolderId, _b);
      expect(router.currentConfiguration.publicationFolderId, _b);
    });

    test('keeps the link it arrived with in the address while it loads',
        () async {
      await router
          .setNewRoutePath(AppRoutePath.publication(folderId: _b, fileId: 'f'));

      expect(router.currentConfiguration.publicationFolderId, _b);
      expect(router.currentConfiguration.publicationFileId, 'f');
    });

    test('a link outside a folder publication lands on its root', () async {
      await router.setNewRoutePath(AppRoutePath.publication(folderId: _c));
      await router.openPublication(
          _config(const PublicationFolderScope(_a)), db.driveDao);

      expect(router.driveFolderId, _a);
    });

    test('a link followed after opening is checked the same way', () async {
      await router.openPublication(
          _config(const PublicationDriveScope()), db.driveDao);

      await router.setNewRoutePath(AppRoutePath.publication(folderId: _c));
      expect(router.driveFolderId, _c);

      await router.setNewRoutePath(AppRoutePath.publication(folderId: 'nope'));
      expect(router.driveFolderId, _root);
    });

    test('the explorer is anonymous only once the publication is open',
        () async {
      expect(router.canAnonymouslyShowDriveDetail(ProfilePromptAdd()), isFalse);

      await router.openPublication(
          _config(const PublicationDriveScope()), db.driveDao);

      expect(router.canAnonymouslyShowDriveDetail(ProfilePromptAdd()), isTrue);
      expect(
        router.canAnonymouslyShowDriveDetail(ProfileCheckingAvailability()),
        isTrue,
      );
    });
  });
}
