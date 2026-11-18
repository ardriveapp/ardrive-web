import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/create_manifest/create_manifest_cubit.dart';
import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/manifest/domain/exceptions.dart';
import 'package:ardrive/manifest/domain/manifest_repository.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/fake_user.dart';
import '../test_utils/mocks.dart';

class MockFolderRepository extends Mock implements FolderRepository {}

class MockManifestRepository extends Mock implements ManifestRepository {}

class MockArDriveAuth extends Mock implements ArDriveAuth {}

class _FakeUploadParams extends Fake implements ManifestUploadParams {}

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

  setUpAll(() {
    registerFallbackValue(tree);
    registerFallbackValue(tree.folder);
    registerFallbackValue(_FakeUploadParams());
  });

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

  group('the wallet check before uploading', () {
    late MockProfileCubit profile;

    Future<CreateManifestCubit> loaded() async {
      profile = MockProfileCubit();
      final cubit = CreateManifestCubit(
        drive: drive,
        profileCubit: profile,
        manifestRepository: manifestRepository,
        folderRepository: folderRepository,
        auth: MockArDriveAuth(),
      );
      await cubit.stream
          .firstWhere((state) => state is CreateManifestFolderLoadSuccess);
      // Only what uploading does counts.
      clearInteractions(manifestRepository);
      return cubit;
    }

    test('on another wallet, says so and uploads nothing', () async {
      final cubit = await loaded();
      when(() => profile.logoutIfWalletMismatch())
          .thenAnswer((_) async => true);

      await cubit.uploadManifest();

      expect(cubit.state, isA<CreateManifestWalletMismatch>());
      verifyZeroInteractions(manifestRepository);
      await cubit.close();
    });

    test('Wander unavailable, then Cancel: uploads nothing, the screen stays',
        () async {
      final cubit = await loaded();
      final before = cubit.state;
      when(() => profile.logoutIfWalletMismatch()).thenThrow(
        const ArConnectUnavailableException(
          ArConnectUnavailableReason.noAnswer,
        ),
      );

      await cubit.uploadManifest();

      expect(cubit.state, before);
      verifyZeroInteractions(manifestRepository);
      await cubit.close();
    });
  });

  group('after a failed upload', () {
    test('Try again sends the same deployment again from its review', () async {
      final profile = MockProfileCubit();
      when(() => profile.logoutIfWalletMismatch())
          .thenAnswer((_) async => false);
      final auth = MockArDriveAuth();
      when(() => auth.currentUser).thenReturn(fakeUserJson);
      final file = await IOFile.fromData(
        Uint8List(10),
        name: 'site',
        lastModifiedDate: DateTime(2024),
      );
      when(
        () => manifestRepository.checkNameConflictAndReturnExistingFileId(
          driveId: driveId,
          parentFolderId: any(named: 'parentFolderId'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) async => (false, null));
      when(
        () => manifestRepository.getManifestFile(
          parentFolder: any(named: 'parentFolder'),
          manifestName: any(named: 'manifestName'),
          rootFolderNode: any(named: 'rootFolderNode'),
          driveId: driveId,
          fallbackTxId: any(named: 'fallbackTxId'),
        ),
      ).thenAnswer((_) async => file);
      var uploads = 0;
      when(
        () => manifestRepository.uploadManifest(
          params: any(named: 'params'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async {
        uploads++;
        if (uploads == 1) throw Exception('offline');
        return 'data-tx';
      });

      final cubit = CreateManifestCubit(
        drive: drive,
        profileCubit: profile,
        manifestRepository: manifestRepository,
        folderRepository: folderRepository,
        auth: auth,
      );
      await cubit.stream
          .firstWhere((state) => state is CreateManifestFolderLoadSuccess);
      await cubit.checkForConflicts('site');
      expect(cubit.state, isA<CreateManifestUploadReview>());

      await cubit.uploadManifest();
      expect(cubit.state, isA<CreateManifestFailure>());

      await cubit.retryUpload();

      expect(uploads, 2);
      expect(cubit.state, isA<CreateManifestSuccess>());
      expect((cubit.state as CreateManifestSuccess).dataTxId, 'data-tx');
      await cubit.close();
    });

    test('Try again does nothing when nothing has failed', () async {
      final cubit = CreateManifestCubit(
        drive: drive,
        profileCubit: MockProfileCubit(),
        manifestRepository: manifestRepository,
        folderRepository: folderRepository,
        auth: MockArDriveAuth(),
      );
      await cubit.stream
          .firstWhere((state) => state is CreateManifestFolderLoadSuccess);
      final before = cubit.state;

      await cubit.retryUpload();

      expect(cubit.state, before);
      await cubit.close();
    });
  });

  group('a step that writes or pays', () {
    test('two fast presses of Create send one upload', () async {
      final profile = MockProfileCubit();
      final gate = Completer<bool>();
      when(() => profile.logoutIfWalletMismatch())
          .thenAnswer((_) => gate.future);
      final auth = MockArDriveAuth();
      when(() => auth.currentUser).thenReturn(fakeUserJson);
      final file = await IOFile.fromData(
        Uint8List(10),
        name: 'site',
        lastModifiedDate: DateTime(2024),
      );
      when(
        () => manifestRepository.checkNameConflictAndReturnExistingFileId(
          driveId: driveId,
          parentFolderId: any(named: 'parentFolderId'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) async => (false, null));
      when(
        () => manifestRepository.getManifestFile(
          parentFolder: any(named: 'parentFolder'),
          manifestName: any(named: 'manifestName'),
          rootFolderNode: any(named: 'rootFolderNode'),
          driveId: driveId,
          fallbackTxId: any(named: 'fallbackTxId'),
        ),
      ).thenAnswer((_) async => file);
      when(
        () => manifestRepository.uploadManifest(
          params: any(named: 'params'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => 'data-tx');

      final cubit = CreateManifestCubit(
        drive: drive,
        profileCubit: profile,
        manifestRepository: manifestRepository,
        folderRepository: folderRepository,
        auth: auth,
      );
      await cubit.stream
          .firstWhere((state) => state is CreateManifestFolderLoadSuccess);
      await cubit.checkForConflicts('site');

      // The wallet check is still open when the second press lands: the
      // cubit has not emitted its busy state yet.
      final first = cubit.uploadManifest();
      final second = cubit.uploadManifest();
      gate.complete(false);
      await Future.wait([first, second]);

      verify(
        () => manifestRepository.uploadManifest(
          params: any(named: 'params'),
          onProgress: any(named: 'onProgress'),
        ),
      ).called(1);
      await cubit.close();
    });

    test('an empty name is never checked', () async {
      final cubit = CreateManifestCubit(
        drive: drive,
        profileCubit: MockProfileCubit(),
        manifestRepository: manifestRepository,
        folderRepository: folderRepository,
        auth: MockArDriveAuth(),
      );
      await cubit.stream
          .firstWhere((state) => state is CreateManifestFolderLoadSuccess);
      final before = cubit.state;

      await cubit.checkForConflicts('   ');
      await cubit.checkForConflicts('');

      expect(cubit.state, before);
      verifyNever(
        () => manifestRepository.checkNameConflictAndReturnExistingFileId(
          driveId: any(named: 'driveId'),
          parentFolderId: any(named: 'parentFolderId'),
          name: any(named: 'name'),
        ),
      );
      await cubit.close();
    });
  });

  group('a failure never leaves the dialog without a way out', () {
    Future<CreateManifestCubit> loaded({MockArDriveAuth? auth}) async {
      final cubit = CreateManifestCubit(
        drive: drive,
        profileCubit: MockProfileCubit(),
        manifestRepository: manifestRepository,
        folderRepository: folderRepository,
        auth: auth ?? MockArDriveAuth(),
      );
      await cubit.stream
          .firstWhere((state) => state is CreateManifestFolderLoadSuccess);
      return cubit;
    }

    test('a name check that throws ends in a failure, not in Preparing',
        () async {
      when(
        () => manifestRepository.checkNameConflictAndReturnExistingFileId(
          driveId: any(named: 'driveId'),
          parentFolderId: any(named: 'parentFolderId'),
          name: any(named: 'name'),
        ),
      ).thenThrow(ManifestCreationException('lookup failed'));
      final cubit = await loaded();

      await cubit.checkForConflicts('site');

      expect(cubit.state, isA<CreateManifestFailure>());
      expect((cubit.state as CreateManifestFailure).canRetry, isFalse,
          reason: 'there is no review to send again');
      await cubit.close();
    });

    test('folders that cannot be read end in a failure, not in Loading',
        () async {
      when(() => folderRepository.getFolderNode(driveId, rootId))
          .thenThrow(Exception('offline'));
      final cubit = CreateManifestCubit(
        drive: drive,
        profileCubit: MockProfileCubit(),
        manifestRepository: manifestRepository,
        folderRepository: folderRepository,
        auth: MockArDriveAuth(),
      );

      await cubit.stream.firstWhere((state) => state is CreateManifestFailure);
      await cubit.close();
    });

    test(
        'a deployment posted and then not saved says so, and Try again '
        'posts nothing twice', () async {
      final profile = MockProfileCubit();
      when(() => profile.logoutIfWalletMismatch())
          .thenAnswer((_) async => false);
      final auth = MockArDriveAuth();
      when(() => auth.currentUser).thenReturn(fakeUserJson);
      final file = await IOFile.fromData(
        Uint8List(10),
        name: 'site',
        lastModifiedDate: DateTime(2024),
      );
      when(
        () => manifestRepository.checkNameConflictAndReturnExistingFileId(
          driveId: driveId,
          parentFolderId: any(named: 'parentFolderId'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) async => (false, null));
      when(
        () => manifestRepository.getManifestFile(
          parentFolder: any(named: 'parentFolder'),
          manifestName: any(named: 'manifestName'),
          rootFolderNode: any(named: 'rootFolderNode'),
          driveId: driveId,
          fallbackTxId: any(named: 'fallbackTxId'),
        ),
      ).thenAnswer((_) async => file);
      var posts = 0;
      when(
        () => manifestRepository.uploadManifest(
          params: any(named: 'params'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async {
        posts++;
        throw ManifestPostedException('posted-tx', error: Exception('db'));
      });
      final cubit = CreateManifestCubit(
        drive: drive,
        profileCubit: profile,
        manifestRepository: manifestRepository,
        folderRepository: folderRepository,
        auth: auth,
      );
      await cubit.stream
          .firstWhere((state) => state is CreateManifestFolderLoadSuccess);
      await cubit.checkForConflicts('site');
      await cubit.uploadManifest();

      final failure = cubit.state as CreateManifestFailure;
      expect(failure.postedTxId, 'posted-tx');
      expect(failure.canRetry, isFalse);

      await cubit.retryUpload();

      expect(posts, 1, reason: 'a second upload would pay twice');
      expect(cubit.state, failure);
      await cubit.close();
    });
  });
}
