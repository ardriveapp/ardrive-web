import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/domain/publication_scope.dart';
import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/utils.dart';

const _drive = 'c863be1f-a725-4554-9a9e-18268ed8a035';
const _otherDrive = '11111111-1111-4111-8111-111111111111';
const _root = '41520b33-28c1-4892-886b-b845a5709085';
const _a = 'aaaaaaaa-0000-4000-8000-000000000001';
const _b = 'bbbbbbbb-0000-4000-8000-000000000002';
const _c = 'cccccccc-0000-4000-8000-000000000003';
const _x = 'eeeeeeee-0000-4000-8000-000000000005';
const _y = 'ffffffff-0000-4000-8000-000000000006';
const _elsewhere = 'dddddddd-0000-4000-8000-000000000004';
const _hidden = '99999999-0000-4000-8000-000000000007';
const _inHidden = '88888888-0000-4000-8000-000000000008';

PublicationConfig config(PublicationScope scope) => PublicationConfig(
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

void main() {
  late Database db;

  Future<void> folder(
    String id,
    String? parent, {
    String drive = _drive,
    bool hidden = false,
    bool ghost = false,
  }) =>
      db.into(db.folderEntries).insert(FolderEntriesCompanion.insert(
            id: id,
            driveId: drive,
            name: id,
            parentFolderId: Value(parent),
            isHidden: Value(hidden),
            isGhost: Value(ghost),
            path: '',
          ));

  setUp(() async {
    db = getTestDb();
    //   root
    //   ├── a
    //   │   └── b
    //   └── c
    // x and y are each other's parent; elsewhere is in another drive.
    await folder(_root, null);
    await folder(_a, _root);
    await folder(_b, _a);
    await folder(_c, _root);
    await folder(_x, _y);
    await folder(_y, _x);
    await folder(_elsewhere, null, drive: _otherDrive);
    await folder(_hidden, _root, hidden: true);
    await folder(_inHidden, _hidden);
  });

  tearDown(() => db.close());

  Future<bool> inScope(PublicationScope scope, String folderId) =>
      isInPublicationScope(
        driveDao: db.driveDao,
        config: config(scope),
        folderId: folderId,
      );

  group('a drive publication', () {
    const scope = PublicationDriveScope();

    test('holds every folder of its drive', () async {
      for (final id in [_root, _a, _b, _c]) {
        expect(await inScope(scope, id), isTrue, reason: id);
      }
    });

    test('holds nothing of another drive, or unknown', () async {
      expect(await inScope(scope, _elsewhere), isFalse);
      expect(await inScope(scope, 'not-a-folder'), isFalse);
    });

    test('holds no hidden folder, nor anything inside one', () async {
      expect(await inScope(scope, _hidden), isFalse);
      expect(await inScope(scope, _inHidden), isFalse);
    });

    test('holds no ghost folder, which the explorer does not list', () async {
      const ghost = '77777777-0000-4000-8000-000000000009';
      await folder(ghost, _root, ghost: true);
      expect(await inScope(scope, ghost), isFalse);
    });

    test('stops on a loop of parents', () async {
      expect(await inScope(scope, _x), isFalse);
    });
  });

  group('a publication of a hidden folder', () {
    const scope = PublicationFolderScope(_hidden);

    test('shows the folder its owner published, and inside it', () async {
      expect(await inScope(scope, _hidden), isTrue);
      expect(await inScope(scope, _inHidden), isTrue);
    });
  });

  group('a folder publication', () {
    const scope = PublicationFolderScope(_a);

    test('holds its folder and what is under it', () async {
      expect(await inScope(scope, _a), isTrue);
      expect(await inScope(scope, _b), isTrue);
    });

    test('holds nothing beside or above it', () async {
      expect(await inScope(scope, _c), isFalse);
      expect(await inScope(scope, _root), isFalse);
      expect(await inScope(scope, _elsewhere), isFalse);
    });
  });
}
