import 'package:ardrive/download/download_utils.dart';
import 'package:ardrive/library/domain/library_config.dart';
import 'package:ardrive/library/domain/library_mode.dart';
import 'package:ardrive/library/domain/library_scope.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/utils.dart';
import 'library_test_files.dart';

const _drive = 'c863be1f-a725-4554-9a9e-18268ed8a035';
const _root = '41520b33-28c1-4892-886b-b845a5709085';
const _a = 'aaaaaaaa-0000-4000-8000-000000000001';
const _c = 'cccccccc-0000-4000-8000-000000000003';
const _hidden = '99999999-0000-4000-8000-000000000007';
const _ghost = '77777777-0000-4000-8000-000000000009';

LibraryConfig _config(LibraryScope scope) => LibraryConfig(
      version: 1,
      driveId: _drive,
      rootFolderId: _root,
      scope: scope,
      privacy: 'public',
      owner: 'iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA',
      snapshot: const LibrarySnapshot(path: 'snapshot', txId: 't', tags: {}),
      title: 'The Library',
      description: '',
      images: const LibraryImages(),
      publishedAt: null,
      viewer: null,
    );

/// Downloads and the info panel read a folder's whole tree from the database,
/// which on a library page holds the drive behind the library. They must
/// hand out only what the library shows.
void main() {
  late Database db;

  Future<void> folder(String id, String name, String? parent,
          {bool hidden = false, bool ghost = false}) =>
      db.into(db.folderEntries).insert(FolderEntriesCompanion.insert(
            id: id,
            driveId: _drive,
            name: name,
            parentFolderId: Value(parent),
            isHidden: Value(hidden),
            isGhost: Value(ghost),
            path: '',
          ));

  Future<void> file(String name, String parent,
          {bool hidden = false, String status = TransactionStatus.confirmed}) =>
      insertLibraryFile(db,
          driveId: _drive,
          id: '$name-id',
          name: name,
          parentFolderId: parent,
          hidden: hidden,
          status: status);

  Future<List<String>> download(List<ArDriveDataTableItem> items) async => [
        for (final item in await convertSelectionToMultiDownloadFileList(
            db.driveDao, MockARFSRepository(), items))
          switch (item) {
            MultiDownloadFolder(:final folderPath) => folderPath,
            MultiDownloadFile(:final fileName) => fileName,
            _ => '?',
          },
      ];

  FolderDataTableItem folderItem(String id, String name) => FolderDataTableItem(
        driveId: _drive,
        folderId: id,
        name: name,
        lastUpdated: DateTime.utc(2026),
        dateCreated: DateTime.utc(2026),
        contentType: 'folder',
        index: 0,
        isOwner: false,
      );

  final driveItem = DriveDataItem(
    id: _drive,
    driveId: _drive,
    name: 'The drive',
    lastUpdated: DateTime.utc(2026),
    dateCreated: DateTime.utc(2026),
    index: 0,
    isOwner: false,
  );

  Future<void> open(LibraryScope scope) async {
    LibraryMode.debugSet('library.json');
    LibraryContents.open =
        await LibraryContents.load(db.driveDao, _config(scope));
  }

  setUp(() async {
    db = getTestDb();
    //   root: root.txt
    //   ├── a "Published": a.txt, failed.txt (failed), secret.txt (hidden)
    //   │   ├── hidden "Hidden": h.txt
    //   │   └── ghost "Ghost": g.txt
    //   └── c "Beside": c.txt
    await folder(_root, 'The drive', null);
    await folder(_a, 'Published', _root);
    await folder(_hidden, 'Hidden', _a, hidden: true);
    await folder(_ghost, 'Ghost', _a, ghost: true);
    await folder(_c, 'Beside', _root);
    await file('root.txt', _root);
    await file('a.txt', _a);
    await file('failed.txt', _a, status: TransactionStatus.failed);
    await file('secret.txt', _a, hidden: true);
    await file('h.txt', _hidden);
    await file('g.txt', _ghost);
    await file('c.txt', _c);
  });

  tearDown(() {
    LibraryMode.debugSet(null);
    LibraryContents.open = null;
    return db.close();
  });

  test('a folder download leaves out what the library does not show', () async {
    await open(const LibraryFolderScope(_a));
    expect(await download([folderItem(_a, 'Published')]),
        ['The Library/', 'The Library/a.txt']);
  });

  test("a folder library's drive download is the library, named by its title",
      () async {
    await open(const LibraryFolderScope(_a));
    expect(await download([driveItem]), ['The Library/', 'The Library/a.txt']);
  });

  test('a drive library downloads the drive as the library shows it', () async {
    await open(const LibraryDriveScope());
    expect(await download([driveItem]), [
      'The Library/',
      'The Library/Published/',
      'The Library/Published/a.txt',
      'The Library/Beside/',
      'The Library/Beside/c.txt',
      'The Library/root.txt',
    ]);
  });

  test('a folder outside the library downloads nothing', () async {
    await open(const LibraryFolderScope(_a));
    expect(await download([folderItem(_c, 'Beside')]), isEmpty);
  });

  test('nothing downloads before the library is open', () async {
    LibraryMode.debugSet('library.json');
    expect(await download([folderItem(_a, 'Published')]), isEmpty);
  });

  test('the app itself still downloads the whole tree', () async {
    final names = await download([folderItem(_a, 'Published')]);
    expect(names, containsAll(['Published/secret.txt', 'Published/Hidden/']));
  });
}
