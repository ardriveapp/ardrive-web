import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/domain/publication_stats.dart';
import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/utils.dart';
import '../publication_test_files.dart';

const _drive = 'c863be1f-a725-4554-9a9e-18268ed8a035';
const _root = '41520b33-28c1-4892-886b-b845a5709085';
const _a = 'aaaaaaaa-0000-4000-8000-000000000001';
const _hidden = '99999999-0000-4000-8000-000000000007';

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

void main() {
  late Database db;

  Future<void> folder(
    String id,
    String? parent, {
    bool hidden = false,
    bool ghost = false,
  }) =>
      db.into(db.folderEntries).insert(FolderEntriesCompanion.insert(
            id: id,
            driveId: _drive,
            name: id,
            parentFolderId: Value(parent),
            isHidden: Value(hidden),
            isGhost: Value(ghost),
            path: '',
          ));

  Future<void> file(
    String id,
    String parent,
    int size, {
    bool hidden = false,
    String status = TransactionStatus.confirmed,
  }) =>
      insertPublicationFile(db,
          driveId: _drive,
          id: id,
          name: id,
          parentFolderId: parent,
          size: size,
          hidden: hidden,
          status: status);

  setUp(() async {
    db = getTestDb();
    //   root: r1 (10), r2 hidden (20)
    //   ├── a: a1 (100)
    //   └── hidden folder: h1 (1000)
    await folder(_root, null);
    await folder(_a, _root);
    await folder(_hidden, _root, hidden: true);
    await file('r1', _root, 10);
    await file('r2', _root, 20, hidden: true);
    await file('a1', _a, 100);
    await file('h1', _hidden, 1000);
  });

  tearDown(() => db.close());

  test('a drive publication counts what it shows', () async {
    expect(
      await computePublicationStats(
          db.driveDao, _config(const PublicationDriveScope())),
      const PublicationStats(fileCount: 2, totalSize: 110),
    );
  });

  test('a folder publication counts its folder only', () async {
    expect(
      await computePublicationStats(
          db.driveDao, _config(const PublicationFolderScope(_a))),
      const PublicationStats(fileCount: 1, totalSize: 100),
    );
  });

  test('a publication of a hidden folder counts inside it', () async {
    expect(
      await computePublicationStats(
          db.driveDao, _config(const PublicationFolderScope(_hidden))),
      const PublicationStats(fileCount: 1, totalSize: 1000),
    );
  });

  test('leaves out what is inside a ghost folder', () async {
    const ghost = '66666666-0000-4000-8000-000000000006';
    await folder(ghost, _root, ghost: true);
    await file('g1', ghost, 5000);
    expect(
      await computePublicationStats(
          db.driveDao, _config(const PublicationDriveScope())),
      const PublicationStats(fileCount: 2, totalSize: 110),
    );
  });

  test('leaves out failed and pending uploads, as the explorer does', () async {
    await file('failed', _root, 5000, status: TransactionStatus.failed);
    await file('pending', _a, 7000, status: TransactionStatus.pending);
    expect(
      await computePublicationStats(
          db.driveDao, _config(const PublicationDriveScope())),
      const PublicationStats(fileCount: 2, totalSize: 110),
    );
  });
}
