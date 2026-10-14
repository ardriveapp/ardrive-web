import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/manifest_data.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:test/test.dart';

import '../test_utils/utils.dart';
import 'expected_manifest_data.dart';

void main() {
  const stubEntityId = '00000000-0000-0000-0000-000000000000';
  const stubTxId = '0000000000000000000000000000000000000000001';
  final stubCurrentDate = DateTime.now();

  late final FileRepository fileRepository;
  late final FolderRepository folderRepository;

  final stubRootFolderEntry = FolderEntry(
    id: 'stubRootFolderEntry',
    dateCreated: stubCurrentDate,
    driveId: stubEntityId,
    isGhost: false,
    parentFolderId: stubEntityId,
    name: 'root-folder',
    lastUpdated: stubCurrentDate,
    isHidden: false,
    path: '',
  );

  final stubParentFolderEntry = FolderEntry(
    id: 'stubParentFolderEntry',
    dateCreated: stubCurrentDate,
    driveId: stubEntityId,
    isGhost: false,
    parentFolderId: stubEntityId,
    name: 'parent-folder',
    lastUpdated: stubCurrentDate,
    isHidden: false,
    path: '',
  );

  final stubChildFolderEntry = FolderEntry(
    id: 'stubChildFolderEntry',
    dateCreated: stubCurrentDate,
    driveId: stubEntityId,
    isGhost: false,
    parentFolderId: stubEntityId,
    name: 'child-folder',
    lastUpdated: stubCurrentDate,
    isHidden: false,
    path: '',
  );

  final stubFileInRoot1 = FileEntry(
    dataTxId: stubTxId,
    dateCreated: stubCurrentDate,
    size: 10,
    name: 'file-in-root-1',
    parentFolderId: stubEntityId,
    lastUpdated: stubCurrentDate,
    lastModifiedDate: stubCurrentDate,
    id: 'file-in-root-1-entity-id',
    driveId: stubEntityId,
    isHidden: false,
    path: '',
  );

  final stubFileInRoot2 = FileEntry(
    dataTxId: stubTxId,
    dateCreated: stubCurrentDate,
    size: 10,
    name: 'file-in-root-2',
    parentFolderId: stubEntityId,
    lastUpdated: stubCurrentDate,
    lastModifiedDate: stubCurrentDate,
    id: 'file-in-root-2-entity-id',
    driveId: stubEntityId,
    isHidden: false,
    path: '',
  );

  final stubFileInParent1 = FileEntry(
    dataTxId: stubTxId,
    dateCreated: stubCurrentDate,
    size: 10,
    name: 'file-in-parent-1',
    parentFolderId: stubEntityId,
    lastUpdated: stubCurrentDate,
    lastModifiedDate: stubCurrentDate,
    id: 'file-in-parent-1-entity-id',
    driveId: stubEntityId,
    isHidden: false,
    path: '',
  );

  final stubFileInParent2 = FileEntry(
    dataTxId: stubTxId,
    dateCreated: stubCurrentDate,
    size: 10,
    name: 'file-in-parent-2',
    parentFolderId: stubEntityId,
    lastUpdated: stubCurrentDate,
    lastModifiedDate: stubCurrentDate,
    id: 'file-in-parent-2-entity-id',
    driveId: stubEntityId,
    isHidden: false,
    path: '',
  );

  final stubFileInChild1 = FileEntry(
    dataTxId: stubTxId,
    dateCreated: stubCurrentDate,
    size: 10,
    name: 'file-in-child-1',
    parentFolderId: stubEntityId,
    lastUpdated: stubCurrentDate,
    lastModifiedDate: stubCurrentDate,
    id: 'file-in-child-1-entity-id',
    driveId: stubEntityId,
    isHidden: false,
    path: '',
  );

  final stubFileInChild2 = FileEntry(
    dataTxId: stubTxId,
    dateCreated: stubCurrentDate,
    size: 10,
    name: 'file-in-child-2',
    parentFolderId: stubEntityId,
    lastUpdated: stubCurrentDate,
    lastModifiedDate: stubCurrentDate,
    id: 'file-in-child-2-entity-id',
    driveId: stubEntityId,
    isHidden: false,
    path: '',
  );

  final stubManifestFileInChild = FileEntry(
    dataTxId: stubTxId,
    dateCreated: stubCurrentDate,
    size: 10,
    name: 'manifest-file-in-child',
    parentFolderId: stubEntityId,
    lastUpdated: stubCurrentDate,
    lastModifiedDate: stubCurrentDate,
    id: 'manifest-file-in-child-entity-id',
    driveId: stubEntityId,
    dataContentType: ContentType.manifest,
    isHidden: false,
    path: '',
  );

  final stubChildFolderNode =
      FolderNode(folder: stubChildFolderEntry, subfolders: [], files: {
    stubFileInChild1.id: stubFileInChild1,
    stubFileInChild2.id: stubFileInChild2,
    stubManifestFileInChild.id: stubManifestFileInChild
  });

  final stubParentFolderNode =
      FolderNode(folder: stubParentFolderEntry, subfolders: [
    stubChildFolderNode
  ], files: {
    stubFileInParent1.id: stubFileInParent1,
    stubFileInParent2.id: stubFileInParent2,
  });

  final stubRootFolderNode =
      FolderNode(folder: stubRootFolderEntry, subfolders: [
    stubParentFolderNode
  ], files: {
    stubFileInRoot1.id: stubFileInRoot1,
    stubFileInRoot2.id: stubFileInRoot2,
  });

  setUpAll(() {
    fileRepository = MockFileRepository();
    folderRepository = MockFolderRepository();

    when(() => folderRepository.getFolderPath(
            stubRootFolderNode.folder.driveId, stubRootFolderNode.folder.id))
        .thenAnswer((_) async => 'root-folder');
    when(() => folderRepository.getFolderPath(
            stubParentFolderEntry.driveId, stubParentFolderEntry.id))
        .thenAnswer((_) async => 'root-folder/parent-folder');
    when(() => folderRepository.getFolderPath(
            stubChildFolderEntry.driveId, stubChildFolderEntry.id))
        .thenAnswer((_) async => 'root-folder/parent-folder/child-folder');

    when(() => fileRepository.getFilePath(
            stubFileInRoot1.driveId, stubFileInRoot1.id))
        .thenAnswer((_) async => 'root-folder/file-in-root-1');
    when(() => fileRepository.getFilePath(
            stubFileInRoot2.driveId, stubFileInRoot2.id))
        .thenAnswer((_) async => 'root-folder/file-in-root-2');
    when(() => fileRepository.getFilePath(
            stubFileInParent1.driveId, stubFileInParent1.id))
        .thenAnswer((_) async => 'root-folder/parent-folder/file-in-parent-1');
    when(() => fileRepository.getFilePath(
            stubFileInParent2.driveId, stubFileInParent2.id))
        .thenAnswer((_) async => 'root-folder/parent-folder/file-in-parent-2');
    when(() =>
        fileRepository.getFilePath(
            stubFileInChild1.driveId, stubFileInChild1.id)).thenAnswer(
        (_) async => 'root-folder/parent-folder/child-folder/file-in-child-1');
    when(() =>
        fileRepository.getFilePath(
            stubFileInChild2.driveId, stubFileInChild2.id)).thenAnswer(
        (_) async => 'root-folder/parent-folder/child-folder/file-in-child-2');
  });
  group('ManifestDataBuilder Tests', () {
    test('returns a ManifestEntity with a valid expected manifest shape',
        () async {
      final builder = ManifestDataBuilder(
        folderRepository: folderRepository,
        fileRepository: fileRepository,
      );

      final manifest = await builder.build(folderNode: stubRootFolderNode);

      expect(
          manifest.toJson(),
          equals({
            'manifest': 'arweave/paths',
            'version': '0.2.0',
            'index': {'path': 'file-in-root-1'},
            'paths': {
              'file-in-root-1': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'file-in-root-2': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'parent-folder/file-in-parent-1': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'parent-folder/file-in-parent-2': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'parent-folder/child-folder/file-in-child-1': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'parent-folder/child-folder/file-in-child-2': {
                'id': '0000000000000000000000000000000000000000001'
              }
            }
          }));
    });

    test(
        'returns a ManifestEntity with a valid expected manifest shape when a fallback is provided',
        () async {
      final builder = ManifestDataBuilder(
        folderRepository: folderRepository,
        fileRepository: fileRepository,
      );

      final manifest = await builder.build(
        folderNode: stubRootFolderNode,
        fallbackTxId: 'fallback-tx-id',
      );

      expect(
          manifest.toJson(),
          equals({
            'manifest': 'arweave/paths',
            'version': '0.2.0',
            'index': {'path': 'file-in-root-1'},
            'fallback': {'id': 'fallback-tx-id'},
            'paths': {
              'file-in-root-1': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'file-in-root-2': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'parent-folder/file-in-parent-1': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'parent-folder/file-in-parent-2': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'parent-folder/child-folder/file-in-child-1': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'parent-folder/child-folder/file-in-child-2': {
                'id': '0000000000000000000000000000000000000000001'
              }
            }
          }));
    });

    test(
        'returns a ManifestEntity with a valid expected manifest shape with a nested child folder',
        () async {
      final builder = ManifestDataBuilder(
        folderRepository: folderRepository,
        fileRepository: fileRepository,
      );

      final manifest = await builder.build(
        folderNode: stubChildFolderNode,
      );

      expect(
          manifest.toJson(),
          equals({
            'manifest': 'arweave/paths',
            'version': '0.2.0',
            'index': {'path': 'file-in-child-1'},
            'paths': {
              'file-in-child-1': {
                'id': '0000000000000000000000000000000000000000001'
              },
              'file-in-child-2': {
                'id': '0000000000000000000000000000000000000000001'
              }
            }
          }));
    });

    group('asPreparedDataItem method', () {
      PackageInfo.setMockInitialValues(
        version: '1.3.3.7',
        packageName: 'ArDrive-Web-Test',
        appName: 'ArDrive-Web-Test',
        buildNumber: '420',
        buildSignature: 'Test signature',
      );

      test('returns a DataItem with the expected tags, owner, and data',
          () async {
        final builder = ManifestDataBuilder(
          folderRepository: folderRepository,
          fileRepository: fileRepository,
        );

        final manifest = await builder.build(
          folderNode: stubRootFolderNode,
        );

        final wallet = getTestWallet();

        AppPlatform.setMockPlatform(platform: SystemPlatform.Android);

        final dataItem = await manifest.asPreparedDataItem(
          owner: await wallet.getOwner(),
        );

        logger.d(dataItem.data.toString());

        expect(dataItem.tags.length, equals(5));
        expect(decodeBase64ToString(dataItem.tags[0].name), equals('App-Name'));
        expect(decodeBase64ToString(dataItem.tags[0].value),
            equals('ArDrive-App'));
        expect(decodeBase64ToString(dataItem.tags[1].name),
            equals('App-Platform'));
        expect(decodeBase64ToString(dataItem.tags[1].value), equals('Android'));
        expect(
            decodeBase64ToString(dataItem.tags[2].name), equals('App-Version'));
        expect(decodeBase64ToString(dataItem.tags[2].value), equals('1.3.3.7'));
        expect(
            decodeBase64ToString(dataItem.tags[3].name), equals('Unix-Time'));
        expect(decodeBase64ToString(dataItem.tags[3].value).length, equals(10));
        expect(decodeBase64ToString(dataItem.tags[4].name),
            equals('Content-Type'));
        expect(decodeBase64ToString(dataItem.tags[4].value),
            equals('application/x.arweave-manifest+json'));

        expect(dataItem.target, equals(''));
        expect(dataItem.owner, equals(await wallet.getOwner()));

        expect(dataItem.data, equals(expectedManifestDataVersion020));
      });
      test(
          'returns a DataItem with the expected tags, owner, and data with fallback',
          () async {
        final builder = ManifestDataBuilder(
          folderRepository: folderRepository,
          fileRepository: fileRepository,
        );

        final manifest = await builder.build(
          folderNode: stubRootFolderNode,
          fallbackTxId: 'fallback-tx-id',
        );

        final wallet = getTestWallet();

        AppPlatform.setMockPlatform(platform: SystemPlatform.Android);

        final dataItem = await manifest.asPreparedDataItem(
          owner: await wallet.getOwner(),
        );

        expect(dataItem.tags.length, equals(5));
        expect(decodeBase64ToString(dataItem.tags[0].name), equals('App-Name'));
        expect(decodeBase64ToString(dataItem.tags[0].value),
            equals('ArDrive-App'));
        expect(decodeBase64ToString(dataItem.tags[1].name),
            equals('App-Platform'));
        expect(decodeBase64ToString(dataItem.tags[1].value), equals('Android'));
        expect(
            decodeBase64ToString(dataItem.tags[2].name), equals('App-Version'));
        expect(decodeBase64ToString(dataItem.tags[2].value), equals('1.3.3.7'));
        expect(
            decodeBase64ToString(dataItem.tags[3].name), equals('Unix-Time'));
        expect(decodeBase64ToString(dataItem.tags[3].value).length, equals(10));
        expect(decodeBase64ToString(dataItem.tags[4].name),
            equals('Content-Type'));
        expect(decodeBase64ToString(dataItem.tags[4].value),
            equals('application/x.arweave-manifest+json'));

        expect(dataItem.target, equals(''));
        expect(dataItem.owner, equals(await wallet.getOwner()));

        expect(dataItem.data, equals(expectedManifestDataWithFallback));
      });
    });
  });

  group('ManifestDataBuilder, what is published and at which path', () {
    const driveId = '00000000-0000-0000-0000-000000000000';
    final now = DateTime(2026, 10, 14);

    late MockFileRepository files;
    late MockFolderRepository folders;
    late ManifestDataBuilder builder;

    FolderEntry folder(String id, {bool isHidden = false}) => FolderEntry(
          id: id,
          dateCreated: now,
          driveId: driveId,
          isGhost: false,
          parentFolderId: driveId,
          name: id,
          lastUpdated: now,
          isHidden: isHidden,
          path: '',
        );

    FileEntry file(
      String id,
      String name, {
      bool isHidden = false,
      DateTime? created,
    }) =>
        FileEntry(
          dataTxId: 'data-$id',
          dateCreated: created ?? now,
          size: 10,
          name: name,
          parentFolderId: driveId,
          lastUpdated: now,
          lastModifiedDate: now,
          id: id,
          driveId: driveId,
          isHidden: isHidden,
          path: '',
        );

    FolderNode node(
      FolderEntry entry, {
      List<FileEntry> children = const [],
      List<FolderNode> subfolders = const [],
    }) =>
        FolderNode(
          folder: entry,
          subfolders: subfolders,
          files: {for (final f in children) f.id: f},
        );

    /// Places [entry] at [path] under the root folder, which is `root`.
    void at(FileEntry entry, String path) =>
        when(() => files.getFilePath(driveId, entry.id))
            .thenAnswer((_) async => 'root/$path');

    /// Each published path, and the data transaction it serves.
    Map<String, String> published(ManifestData manifest) =>
        {for (final e in manifest.paths.entries) e.key: e.value.id};

    setUp(() {
      files = MockFileRepository();
      folders = MockFolderRepository();
      builder = ManifestDataBuilder(
        fileRepository: files,
        folderRepository: folders,
      );
      when(() => folders.getFolderPath(driveId, 'root'))
          .thenAnswer((_) async => 'root');
    });

    group('hidden items', () {
      test('leaves out everything inside a hidden folder, however deep',
          () async {
        final readme = file('readme', 'readme.txt');
        final notes = file('notes', 'notes.txt');
        final deep = file('deep', 'deep.txt');
        at(readme, 'readme.txt');
        at(notes, 'secret/notes.txt');
        at(deep, 'secret/deeper/deep.txt');

        final manifest = await builder.build(
          folderNode: node(
            folder('root'),
            children: [readme],
            subfolders: [
              node(
                folder('secret', isHidden: true),
                children: [notes],
                subfolders: [
                  node(folder('deeper'), children: [deep])
                ],
              ),
            ],
          ),
        );

        expect(published(manifest), {'readme.txt': 'data-readme'});
      });

      test('still leaves out a hidden file in a visible folder', () async {
        final shown = file('shown', 'shown.txt');
        final hidden = file('hidden', 'hidden.txt', isHidden: true);
        at(shown, 'shown.txt');
        at(hidden, 'hidden.txt');

        final manifest = await builder.build(
          folderNode: node(folder('root'), children: [shown, hidden]),
        );

        expect(published(manifest), {'shown.txt': 'data-shown'});
      });

      test('never makes a hidden index.html the index', () async {
        final index = file('index', 'index.html', isHidden: true);
        final page = file('page', 'page.html');
        at(index, 'index.html');
        at(page, 'page.html');

        final manifest = await builder.build(
          folderNode: node(folder('root'), children: [index, page]),
        );

        expect(manifest.index.path, 'page.html');
        expect(published(manifest), {'page.html': 'data-page'});
      });

      test('makes a visible index.html the index over the first file',
          () async {
        final first = file('first', 'a.txt');
        final index = file('index', 'index.html');
        at(first, 'a.txt');
        at(index, 'index.html');

        final manifest = await builder.build(
          folderNode: node(folder('root'), children: [first, index]),
        );

        expect(manifest.index.path, 'index.html');
      });

      test('refuses a folder with nothing left to publish', () async {
        final onlyHidden = file('only', 'only.txt', isHidden: true);
        final insideHiddenFolder = file('inside', 'inside.txt');

        expect(
          () => builder.build(
            folderNode: node(folder('root'), children: [onlyHidden]),
          ),
          throwsA(isA<ManifestHasNoFilesException>()),
        );
        expect(
          () => builder.build(
            folderNode: node(
              folder('root'),
              subfolders: [
                node(
                  folder('secret', isHidden: true),
                  children: [insideHiddenFolder],
                ),
              ],
            ),
          ),
          throwsA(isA<ManifestHasNoFilesException>()),
        );
      });
    });

    group('paths', () {
      test('keeps the underscored path for a name that collides with nothing',
          () async {
        final photo = file('photo', 'holiday photo.jpg');
        at(photo, 'holiday photo.jpg');

        final manifest = await builder.build(
          folderNode: node(folder('root'), children: [photo]),
        );

        expect(published(manifest), {'holiday_photo.jpg': 'data-photo'});
      });

      test(
          'keeps both files whose names differ only by a space and an '
          'underscore, in either order', () async {
        final spaced = file('spaced', 'my file.txt');
        final scored = file('scored', 'my_file.txt');
        at(spaced, 'my file.txt');
        at(scored, 'my_file.txt');

        for (final order in [
          [spaced, scored],
          [scored, spaced],
        ]) {
          final manifest = await builder.build(
            folderNode: node(folder('root'), children: order),
          );

          expect(published(manifest), {
            'my_file.txt': 'data-scored',
            'my file.txt': 'data-spaced',
          });
        }
      });

      test('gives each file its raw path when neither owns the underscored one',
          () async {
        final one = file('one', 'a b_c.txt');
        final two = file('two', 'a_b c.txt');
        at(one, 'a b_c.txt');
        at(two, 'a_b c.txt');

        final manifest = await builder.build(
          folderNode: node(folder('root'), children: [one, two]),
        );

        expect(published(manifest), {
          'a b_c.txt': 'data-one',
          'a_b c.txt': 'data-two',
        });
      });

      test('keeps two files at exactly the same path, the earliest first',
          () async {
        final older = file('older-file-id', 'dup.txt', created: DateTime(2025));
        final newer = file('newer-file-id', 'dup.txt', created: DateTime(2026));
        at(older, 'dup.txt');
        at(newer, 'dup.txt');

        final manifest = await builder.build(
          folderNode: node(folder('root'), children: [newer, older]),
        );

        expect(published(manifest), {
          'dup.txt': 'data-older-file-id',
          'dup~newer-fi.txt': 'data-newer-file-id',
        });
      });

      test('points the index at the path its file was given', () async {
        final spaced = file('spaced', 'index page.html');
        final scored = file('scored', 'index_page.html');
        at(spaced, 'index page.html');
        at(scored, 'index_page.html');

        final manifest = await builder.build(
          folderNode: node(folder('root'), children: [spaced, scored]),
        );

        expect(manifest.index.path, 'index page.html');
        expect(published(manifest).keys, contains(manifest.index.path));
      });
    });
  });
}
