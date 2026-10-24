import 'package:ardrive/models/models.dart';
import 'package:ardrive/publication/domain/publication_scope.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/utils.dart';
import '../publication_test_files.dart';

const _drive = 'c863be1f-a725-4554-9a9e-18268ed8a035';
const _root = '41520b33-28c1-4892-886b-b845a5709085';
const _photos = 'aaaaaaaa-0000-4000-8000-000000000001';
const _deep = 'bbbbbbbb-0000-4000-8000-000000000002';
const _hidden = '99999999-0000-4000-8000-000000000007';
const _ghost = '77777777-0000-4000-8000-000000000009';

void main() {
  late Database db;

  Future<void> folder(String id, String? parent,
          {bool hidden = false, bool ghost = false, String? name}) =>
      db.into(db.folderEntries).insert(FolderEntriesCompanion.insert(
            id: id,
            driveId: _drive,
            name: name ?? id,
            parentFolderId: Value(parent),
            isHidden: Value(hidden),
            isGhost: Value(ghost),
            path: '',
          ));

  Future<void> file(String id, String parent,
          {int size = 10,
          bool hidden = false,
          String status = TransactionStatus.confirmed}) =>
      insertPublicationFile(db,
          driveId: _drive,
          id: id,
          name: '$id.txt',
          parentFolderId: parent,
          size: size,
          hidden: hidden,
          status: status);

  setUp(() async {
    db = getTestDb();
    //   root: a, h (hidden), p (pending), f (failed)
    //   ├── Photos: b
    //   │   └── Deep: c
    //   ├── hidden folder: d (left out with its folder)
    //   └── ghost folder: g
    await folder(_root, null);
    await folder(_photos, _root, name: 'Photos');
    await folder(_deep, _photos, name: 'Deep');
    await folder(_hidden, _root, hidden: true);
    await folder(_ghost, _root, ghost: true);
    await file('a', _root, size: 100);
    await file('h', _root, hidden: true);
    await file('p', _root, status: TransactionStatus.pending);
    await file('f', _root, status: TransactionStatus.failed);
    await file('b', _photos, size: 20);
    await file('c', _deep, size: 3);
    await file('d', _hidden);
    await file('g', _ghost);
  });

  tearDown(() => db.close());

  Future<PublicationContents> scope(String top) =>
      PublicationContents.loadScope(db.driveDao,
          driveId: _drive, rootFolderId: _root, scopeRootFolderId: top);

  test('a drive counts what it lists and says what it leaves out', () async {
    final summary = (await scope(_root)).summarize();
    expect(summary.fileCount, 3);
    expect(summary.totalSize, 123);
    expect(summary.folderCount, 2);
    expect(summary.hiddenItems, 2, reason: 'the hidden file and folder');
    expect(summary.inHiddenFolders, 1, reason: 'd');
    expect(summary.inGhostFolders, 1, reason: 'g');
    expect(summary.pendingFiles, 1);
    expect(summary.failedFiles, 1);
    expect(summary.leavesOut, isTrue);
  });

  test('a folder counts only what is under it', () async {
    final summary = (await scope(_photos)).summarize();
    expect(summary.fileCount, 2);
    expect(summary.totalSize, 23);
    expect(summary.folderCount, 1);
    expect(summary.leavesOut, isFalse);
  });

  test('a folder with nothing listed is empty', () async {
    await folder('eeeeeeee-0000-4000-8000-00000000000e', _root);
    final summary =
        (await scope('eeeeeeee-0000-4000-8000-00000000000e')).summarize();
    expect(summary.isEmpty, isTrue);
  });

  test('files.html lists paths below the top folder, sorted', () async {
    final listed = (await scope(_root)).listedFiles();
    expect(
      [for (final f in listed) f.path.join('/')],
      ['Photos/Deep/c.txt', 'Photos/b.txt', 'a.txt'],
    );
    expect(listed.last.dataTxId, 'aData');
    final inFolder = (await scope(_photos)).listedFiles();
    expect(
        [for (final f in inFolder) f.path.join('/')], ['Deep/c.txt', 'b.txt']);
  });
}
