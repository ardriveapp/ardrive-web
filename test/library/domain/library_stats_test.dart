import 'package:ardrive/library/domain/library_config.dart';
import 'package:ardrive/library/domain/library_stats.dart';
import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/utils.dart';

const _drive = 'c863be1f-a725-4554-9a9e-18268ed8a035';
const _root = '41520b33-28c1-4892-886b-b845a5709085';
const _a = 'aaaaaaaa-0000-4000-8000-000000000001';
const _hidden = '99999999-0000-4000-8000-000000000007';

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

  Future<void> file(String id, String parent, int size,
          {bool hidden = false}) =>
      db.into(db.fileEntries).insert(FileEntriesCompanion.insert(
            id: id,
            driveId: _drive,
            parentFolderId: parent,
            name: id,
            dataTxId: '${id}Data',
            size: size,
            lastModifiedDate: DateTime.utc(2026),
            isHidden: Value(hidden),
            path: '',
          ));

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

  test('a drive library counts what it shows', () async {
    expect(
      await computeLibraryStats(
          db.driveDao, _config(const LibraryDriveScope())),
      const LibraryStats(fileCount: 2, totalSize: 110),
    );
  });

  test('a folder library counts its folder only', () async {
    expect(
      await computeLibraryStats(
          db.driveDao, _config(const LibraryFolderScope(_a))),
      const LibraryStats(fileCount: 1, totalSize: 100),
    );
  });

  test('a library of a hidden folder counts inside it', () async {
    expect(
      await computeLibraryStats(
          db.driveDao, _config(const LibraryFolderScope(_hidden))),
      const LibraryStats(fileCount: 1, totalSize: 1000),
    );
  });

  test('leaves out what is inside a ghost folder', () async {
    const ghost = '66666666-0000-4000-8000-000000000006';
    await folder(ghost, _root, ghost: true);
    await file('g1', ghost, 5000);
    expect(
      await computeLibraryStats(
          db.driveDao, _config(const LibraryDriveScope())),
      const LibraryStats(fileCount: 2, totalSize: 110),
    );
  });
}
