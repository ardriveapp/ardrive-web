import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:arweave/arweave.dart' show TransactionResult;
import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/create_manifest/create_manifest_cubit.dart';
import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
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

    test('Try again pays the way the failed try did, the wallet included',
        () async {
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
      final types = <UploadType>[];
      when(
        () => manifestRepository.uploadManifest(
          params: any(named: 'params'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((invocation) async {
        types.add((invocation.namedArguments[#params] as ManifestUploadParams)
            .uploadType);
        if (types.length == 1) throw Exception('offline');
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

      // The review sends the method it showed; the review state itself
      // never held it.
      await cubit.uploadManifest(method: UploadMethod.ar);
      expect(cubit.state, isA<CreateManifestFailure>());
      await cubit.retryUpload();

      expect(types, [UploadType.d2n, UploadType.d2n]);
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

  group('a failed upload that may have been submitted', () {
    late IOFile ioFile;
    setUp(() async {
      ioFile = await IOFile.fromData(Uint8List(1),
          name: 'site', lastModifiedDate: DateTime(2024));
    });

    FileUploadTask task({
      required UploadType type,
      bool metadataUploaded = false,
      Object? error,
      bool built = false,
    }) =>
        FileUploadTask(
          file: ioFile,
          metadata: ARFSFileUploadMetadata(
            size: 1,
            lastModifiedDate: DateTime(2024),
            dataContentType: 'application/x.arweave-manifest+json',
            driveId: driveId,
            parentFolderId: rootId,
            name: 'site',
            id: 'file-id',
            isPrivate: false,
          ),
          type: type,
          metadataUploaded: metadataUploaded,
          error: error,
          uploadThumbnail: false,
          uploadItem: built
              ? TransactionUploadItem(size: 1, data: _FakeTransactionResult())
              : null,
        );

    /// The cubit's state after one upload that failed with [failure].
    Future<CreateManifestFailure> failedWith(
      Object failure, {
      UploadMethod method = UploadMethod.turbo,
    }) async {
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
      when(
        () => manifestRepository.uploadManifest(
          params: any(named: 'params'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => throw failure);

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
      await cubit.uploadManifest(method: method);
      final state = cubit.state as CreateManifestFailure;
      await cubit.close();
      return state;
    }

    ManifestCreationException wrapping(Object e) =>
        ManifestCreationException('Failed to upload manifest.', error: e);

    test(
        'Turbo took the metadata item: no Try again, the data is not paid '
        'for a second time', () async {
      final failure = await failedWith(wrapping([
        task(
          type: UploadType.turbo,
          metadataUploaded: true,
          error: DataTransactionUploadException(message: 'data failed'),
        ),
      ]));

      expect(failure.canRetry, isFalse);
      expect(failure.maybeSent, isTrue);
    });

    test('Turbo took nothing: Try again is offered', () async {
      final failure = await failedWith(wrapping([
        task(
          type: UploadType.turbo,
          error: MetadataTransactionUploadException(message: 'refused'),
        ),
      ]));

      expect(failure.canRetry, isTrue);
      expect(failure.maybeSent, isFalse);
    });

    test('a payment refusal after the metadata item keeps it too', () async {
      final failure = await failedWith(wrapping(UnderFundException(
        message: 'pay',
        error: [
          task(
            type: UploadType.turbo,
            metadataUploaded: true,
            error: DataTransactionUploadException(message: 'data failed'),
          ),
        ],
      )));

      expect(failure.canRetry, isFalse);
      expect(failure.maybeSent, isTrue);
    });

    // What the bundle strategy throws for a direct upload: a
    // BundleUploadException, wrapping the header or chunk failure.
    test(
        'direct: the chunks failed after the transaction was built, no Try '
        'again', () async {
      final failure = await failedWith(
        wrapping([
          task(
            type: UploadType.d2n,
            built: true,
            error: BundleUploadException(
              message: 'chunks',
              error: Exception('chunk stream broke'),
            ),
          ),
        ]),
        method: UploadMethod.ar,
      );

      expect(failure.canRetry, isFalse);
      expect(failure.maybeSent, isTrue);
    });

    // A failed header post does not show the header missed the network.
    test('direct: a header post that failed is not proof nothing was sent',
        () async {
      final failure = await failedWith(
        wrapping([
          task(
            type: UploadType.d2n,
            built: true,
            error: BundleUploadException(
              message: 'header',
              error: TransactionHeaderNotPostedException(),
            ),
          ),
        ]),
        method: UploadMethod.ar,
      );

      expect(failure.canRetry, isFalse);
      expect(failure.maybeSent, isTrue);
    });

    test('direct: a failure before the transaction was built offers Try again',
        () async {
      final failure = await failedWith(
        wrapping([
          task(
            type: UploadType.d2n,
            error: BundleUploadException(
              message: 'bundle',
              error: Exception('could not sign'),
            ),
          ),
        ]),
        method: UploadMethod.ar,
      );

      expect(failure.canRetry, isTrue);
      expect(failure.maybeSent, isFalse);
    });

    test('direct: a cancel sent nothing more', () async {
      final failure = await failedWith(
        wrapping([
          task(
            type: UploadType.d2n,
            built: true,
            error: UploadCanceledException('Upload canceled'),
          ),
        ]),
        method: UploadMethod.ar,
      );

      expect(failure.canRetry, isTrue);
    });
  });

  group('the review is what was approved', () {
    test('a change under the wallet check does not change what is sent',
        () async {
      final profile = MockProfileCubit();
      final check = Completer<bool>();
      when(() => profile.logoutIfWalletMismatch())
          .thenAnswer((_) => check.future);
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
      final types = <UploadType>[];
      when(
        () => manifestRepository.uploadManifest(
          params: any(named: 'params'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((invocation) async {
        types.add((invocation.namedArguments[#params] as ManifestUploadParams)
            .uploadType);
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

      // Create is pressed on the Turbo review, with no method of its own.
      final sending = cubit.uploadManifest();
      await Future<void>.delayed(Duration.zero);
      // The wallet check is open; the payment method changes under it.
      cubit.selectUploadMethod(
        UploadMethod.ar,
        UploadPaymentMethodInfo(
          uploadMethod: UploadMethod.ar,
          costEstimateAr: UploadCostEstimate(
            pstFee: BigInt.zero,
            totalCost: BigInt.one,
            totalSize: 1,
            usdUploadCost: null,
          ),
          costEstimateTurbo: null,
          hasNoTurboBalance: false,
          isTurboUploadPossible: true,
          arBalance: '0',
          sufficientArBalance: true,
          turboCredits: '0',
          sufficentCreditsBalance: true,
          freeStatus: FreeUploadStatus.notEligible,
          totalSize: 1,
        ),
        true,
      );
      check.complete(false);
      await sending;

      expect(types, [UploadType.turbo]);
      await cubit.close();
    });
  });

  group('a folder that has not arrived yet', () {
    test('is not deployed to: the check waits for the folder shown', () async {
      final gate = StreamController<FolderWithContents>();
      when(
        () => folderRepository.watchFolderContents(
          driveId: driveId,
          folderId: 'docs',
        ),
      ).thenAnswer((_) => gate.stream);
      final cubit = CreateManifestCubit(
        drive: drive,
        profileCubit: MockProfileCubit(),
        manifestRepository: manifestRepository,
        folderRepository: folderRepository,
        auth: MockArDriveAuth(),
      );
      await cubit.stream
          .firstWhere((state) => state is CreateManifestFolderLoadSuccess);
      clearInteractions(manifestRepository);
      final shown = cubit.state as CreateManifestFolderLoadSuccess;
      expect(cubit.isLoadingFolder(shown), isFalse);

      await cubit.loadFolder('docs');
      expect(cubit.isLoadingFolder(shown), isTrue);
      await cubit.checkForConflicts('site');

      expect(cubit.state, shown, reason: 'nothing was checked');
      verifyZeroInteractions(manifestRepository);

      gate.add(FolderWithContents(
        folder: folder('docs', parent: rootId),
        subfolders: const [],
        files: const [],
      ));
      await Future<void>.delayed(Duration.zero);
      expect(
        cubit.isLoadingFolder(cubit.state as CreateManifestFolderLoadSuccess),
        isFalse,
      );
      await cubit.close();
      await gate.close();
    });
  });

  test('two quick folder clicks show the one asked for last', () async {
    final docs = StreamController<FolderWithContents>();
    final img = StreamController<FolderWithContents>();
    when(() => folderRepository.watchFolderContents(
        driveId: driveId, folderId: 'docs')).thenAnswer((_) => docs.stream);
    when(() => folderRepository.watchFolderContents(
        driveId: driveId, folderId: 'img')).thenAnswer((_) => img.stream);
    final cubit = CreateManifestCubit(
      drive: drive,
      profileCubit: MockProfileCubit(),
      manifestRepository: manifestRepository,
      folderRepository: folderRepository,
      auth: MockArDriveAuth(),
    );
    await cubit.stream
        .firstWhere((state) => state is CreateManifestFolderLoadSuccess);

    // Neither awaited: both pass the cancel of the folder before.
    unawaited(cubit.loadFolder('docs'));
    unawaited(cubit.loadFolder('img'));
    await Future<void>.delayed(Duration.zero);
    img.add(FolderWithContents(
      folder: folder('img', parent: rootId),
      subfolders: const [],
      files: const [],
    ));
    await Future<void>.delayed(Duration.zero);
    docs.add(FolderWithContents(
      folder: folder('docs', parent: rootId),
      subfolders: const [],
      files: const [],
    ));
    await Future<void>.delayed(Duration.zero);

    final shown = cubit.state as CreateManifestFolderLoadSuccess;
    expect(shown.viewingFolder.folder.id, 'img');
    expect(cubit.isLoadingFolder(shown), isFalse);
    await cubit.close();
    await docs.close();
    await img.close();
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
      expect(failure.maybeSent, isFalse, reason: 'it names the transaction');

      await cubit.retryUpload();

      expect(posts, 1, reason: 'a second upload would pay twice');
      expect(cubit.state, failure);
      await cubit.close();
    });
  });
}

class _FakeTransactionResult extends Fake implements TransactionResult {}
