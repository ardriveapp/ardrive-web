import 'package:ardrive/download/download_utils.dart';
import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/publication/domain/publication_scope.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/utils.dart';
import 'publication_test_files.dart';

const _drive = 'c863be1f-a725-4554-9a9e-18268ed8a035';
const _root = '41520b33-28c1-4892-886b-b845a5709085';
const _a = 'aaaaaaaa-0000-4000-8000-000000000001';
const _c = 'cccccccc-0000-4000-8000-000000000003';
const _hidden = '99999999-0000-4000-8000-000000000007';
const _ghost = '77777777-0000-4000-8000-000000000009';

PublicationConfig _config(PublicationScope scope) => PublicationConfig(
      version: 1,
      driveId: _drive,
      rootFolderId: _root,
      scope: scope,
      privacy: 'public',
      owner: 'iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA',
      snapshot:
          const PublicationSnapshot(path: 'snapshot', txId: 't', tags: {}),
      title: 'The Publication',
      description: '',
      images: const PublicationImages(),
      publishedAt: null,
      viewer: null,
    );

/// Downloads and the info panel read a folder's whole tree from the database,
/// which on a publication holds the drive behind the publication. They must
/// hand out only what the publication shows.
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
      insertPublicationFile(db,
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

  Future<void> open(PublicationScope scope) async {
    PublicationMode.debugSet('publication.json');
    PublicationContents.open =
        await PublicationContents.load(db.driveDao, _config(scope));
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
    PublicationMode.debugSet(null);
    PublicationContents.open = null;
    return db.close();
  });

  test('a folder download leaves out what the publication does not show',
      () async {
    await open(const PublicationFolderScope(_a));
    expect(await download([folderItem(_a, 'Published')]),
        ['The Publication/', 'The Publication/a.txt']);
  });

  test(
      "a folder publication's drive download is the publication, named by its title",
      () async {
    await open(const PublicationFolderScope(_a));
    expect(await download([driveItem]),
        ['The Publication/', 'The Publication/a.txt']);
  });

  test('a drive publication downloads the drive as the publication shows it',
      () async {
    await open(const PublicationDriveScope());
    expect(await download([driveItem]), [
      'The Publication/',
      'The Publication/Published/',
      'The Publication/Published/a.txt',
      'The Publication/Beside/',
      'The Publication/Beside/c.txt',
      'The Publication/root.txt',
    ]);
  });

  test('a folder outside the publication downloads nothing', () async {
    await open(const PublicationFolderScope(_a));
    expect(await download([folderItem(_c, 'Beside')]), isEmpty);
  });

  test('nothing downloads before the publication is open', () async {
    PublicationMode.debugSet('publication.json');
    expect(await download([folderItem(_a, 'Published')]), isEmpty);
  });

  test('the app itself still downloads the whole tree', () async {
    final names = await download([folderItem(_a, 'Published')]);
    expect(names, containsAll(['Published/secret.txt', 'Published/Hidden/']));
  });
}
