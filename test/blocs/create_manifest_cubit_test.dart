import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/create_manifest/create_manifest_cubit.dart';
import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/manifest/domain/manifest_repository.dart';
import 'package:ardrive/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

class MockFolderRepository extends Mock implements FolderRepository {}

class MockManifestRepository extends Mock implements ManifestRepository {}

class MockArDriveAuth extends Mock implements ArDriveAuth {}

/// Which folder the manifest's folder picker opens in.
void main() {
  const driveId = 'drive-id';
  const rootId = 'root';

  final drive = Drive(
    id: driveId,
    rootFolderId: rootId,
    ownerAddress: 'owner',
    name: 'A public drive',
    privacy: 'public',
    lastBlockHeight: 0,
    isHidden: false,
    dateCreated: DateTime(2024),
    lastUpdated: DateTime(2024),
  );

  FolderEntry folder(String id, {String? parent, bool hidden = false}) =>
      FolderEntry(
        id: id,
        driveId: driveId,
        name: id,
        parentFolderId: parent,
        path: '',
        dateCreated: DateTime(2024),
        lastUpdated: DateTime(2024),
        isGhost: false,
        isHidden: hidden,
      );

  FolderNode node(FolderEntry entry,
          [List<FolderNode> subfolders = const []]) =>
      FolderNode(folder: entry, subfolders: subfolders, files: {});

  // root
  // ├── docs
  // │   └── site
  // └── secret (hidden)
  //     └── inner
  final tree = node(folder(rootId), [
    node(folder('docs', parent: rootId), [
      node(folder('site', parent: 'docs')),
    ]),
    node(folder('secret', parent: rootId, hidden: true), [
      node(folder('inner', parent: 'secret')),
    ]),
  ]);

  late MockFolderRepository folderRepository;
  late MockManifestRepository manifestRepository;

  setUpAll(() => registerFallbackValue(tree));

  setUp(() {
    folderRepository = MockFolderRepository();
    manifestRepository = MockManifestRepository();

    when(() => folderRepository.getFolderNode(driveId, rootId))
        .thenAnswer((_) async => tree);
    when(
      () => folderRepository.watchFolderContents(
        driveId: driveId,
        folderId: any(named: 'folderId'),
      ),
    ).thenAnswer(
      (invocation) => Stream.value(
        FolderWithContents(
          folder: folder(invocation.namedArguments[#folderId] as String),
          subfolders: const [],
          files: const [],
        ),
      ),
    );
    when(
      () => manifestRepository.hasPendingFilesOnTargetFolder(
        folderNode: any(named: 'folderNode'),
      ),
    ).thenAnswer((_) async => false);
  });

  Future<String> openedFolder({String? initialFolderId}) async {
    final cubit = CreateManifestCubit(
      drive: drive,
      initialFolderId: initialFolderId,
      profileCubit: MockProfileCubit(),
      manifestRepository: manifestRepository,
      folderRepository: folderRepository,
      auth: MockArDriveAuth(),
    );
    final loaded = await cubit.stream
        .firstWhere((state) => state is CreateManifestFolderLoadSuccess);
    await cubit.close();
    return (loaded as CreateManifestFolderLoadSuccess).viewingFolder.folder.id;
  }

  test('opens in the folder the user was viewing', () async {
    expect(await openedFolder(initialFolderId: 'site'), 'site');
  });

  test('opens at the root when no folder was given', () async {
    expect(await openedFolder(), rootId);
  });

  test('opens at the root when the folder is the root', () async {
    expect(await openedFolder(initialFolderId: rootId), rootId);
  });

  test('opens at the root instead of in a hidden folder', () async {
    expect(await openedFolder(initialFolderId: 'secret'), rootId);
  });

  test('opens at the root instead of below a hidden folder', () async {
    expect(await openedFolder(initialFolderId: 'inner'), rootId);
  });

  test('opens at the root for a folder that is not in the drive', () async {
    expect(await openedFolder(initialFolderId: 'elsewhere'), rootId);
  });
}
