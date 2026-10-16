import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/utils.dart';

/// `getFolderTree` reads the whole drive in two queries rather than two per
/// folder. This holds it to what the per-folder version returned, which is
/// kept here as the oracle.
void main() {
  late Database db;

  setUp(() => db = getTestDb());
  tearDown(() => db.close());

  /// The previous implementation, verbatim but for its name.
  Future<FolderNode> perFolderTree(String driveId, String rootFolderId) async {
    final dao = db.driveDao;
    final rootFolder = await dao.folderById(folderId: rootFolderId).getSingle();

    Future<FolderNode> getFolderChildren(FolderEntry parentFolder) async {
      final subfolders = await dao
          .foldersInFolder(driveId: driveId, parentFolderId: parentFolder.id)
          .get();
      return FolderNode(
        folder: parentFolder,
        subfolders:
            await Future.wait(subfolders.map((f) => getFolderChildren(f))),
        files: {
          await for (var f in dao
              .filesInFolder(driveId: driveId, parentFolderId: parentFolder.id)
              .get()
              .asStream()
              .expand((f) => f))
            f.id: f
        },
      );
    }

    return getFolderChildren(rootFolder);
  }

  /// The tree as plain data, children in order, so two trees compare equal
  /// only if every folder, file and position matches.
  Object shape(FolderNode node) => {
        'folder': node.folder,
        'files': node.files.entries.map((e) => [e.key, e.value]).toList(),
        'subfolders': node.subfolders.map(shape).toList(),
      };

  Future<void> folder(String driveId, String id, String? parent) =>
      db.into(db.folderEntries).insert(FolderEntriesCompanion.insert(
            id: id,
            driveId: driveId,
            name: 'folder $id',
            parentFolderId: Value(parent),
            path: '',
          ));

  Future<void> file(String driveId, String id, String parent) =>
      db.into(db.fileEntries).insert(FileEntriesCompanion.insert(
            id: id,
            driveId: driveId,
            name: 'file $id',
            parentFolderId: parent,
            path: '',
            size: id.length,
            lastModifiedDate: DateTime(2024),
            dataTxId: 'data-$id',
            dateCreated: Value(DateTime(2024)),
            lastUpdated: Value(DateTime(2024)),
          ));

  test(
      'matches the per-folder tree on a nested drive with another drive '
      'interleaved', () async {
    // Rows written out of tree order, two drives interleaved, a file in
    // every folder and several in some, so order and scoping both show.
    await folder('a', 'root', null);
    await folder('b', 'b-root', null);
    await folder('a', 'f3', 'f1');
    await folder('a', 'f1', 'root');
    await folder('b', 'b-f1', 'b-root');
    await folder('a', 'f2', 'root');
    await folder('a', 'f4', 'f3');
    await folder('a', 'f5', 'root');
    await folder('b', 'f1-in-b', 'f1');
    for (final (id, parent) in [
      ('x9', 'root'),
      ('x1', 'f4'),
      ('x2', 'root'),
      ('x3', 'f1'),
      ('x4', 'f3'),
      ('x5', 'f2'),
      ('x6', 'root'),
      ('x7', 'f4'),
    ]) {
      await file('a', id, parent);
    }
    await file('b', 'b-file', 'f1');
    await file('b', 'b-file-2', 'b-root');

    for (final (drive, root) in [('a', 'root'), ('b', 'b-root')]) {
      final now = await db.driveDao.getFolderTree(drive, root);
      final before = await perFolderTree(drive, root);
      expect(shape(now), shape(before), reason: 'drive $drive');
    }
  });

  test('a subtree, not only the root', () async {
    await folder('a', 'root', null);
    await folder('a', 'f1', 'root');
    await folder('a', 'f2', 'f1');
    await file('a', 'in-f2', 'f2');
    await file('a', 'in-root', 'root');

    expect(
      shape(await db.driveDao.getFolderTree('a', 'f1')),
      shape(await perFolderTree('a', 'f1')),
    );
  });

  test('returns rather than recursing for ever on a cycle in the rows',
      () async {
    await folder('a', 'root', null);
    await folder('a', 'c1', 'c2');
    await folder('a', 'c2', 'c1');
    await folder('a', 'f1', 'root');

    final tree = await db.driveDao.getFolderTree('a', 'c1');
    expect(tree.folder.id, 'c1');
    expect(tree.subfolders.single.folder.id, 'c2');
    expect(tree.subfolders.single.subfolders, isEmpty);
  });
}
