import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/drive_rename/drive_rename_cubit.dart';
import 'package:ardrive/blocs/ghost_fixer/ghost_fixer_cubit.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/user.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

/// Every write below asks first whether Wander is still on the saved
/// account's wallet. On another wallet, nothing is written; when Wander
/// couldn't be reached and the person chose Cancel, nothing is written and
/// the flow ends somewhere the person can close.
void main() {
  const driveId = 'drive-id';
  const rootFolderId = 'root-folder-id';
  const nestedFolderId = 'nested-folder-id';

  late Database db;
  late MockArweaveService arweave;
  late MockProfileCubit profile;

  const unavailable =
      ArConnectUnavailableException(ArConnectUnavailableReason.noAnswer);

  void walletIsElsewhere() => when(() => profile.logoutIfWalletMismatch())
      .thenAnswer((_) async => true);

  void wanderUnavailable() =>
      when(() => profile.logoutIfWalletMismatch()).thenThrow(unavailable);

  Future<int> folderCount() async =>
      (await db.select(db.folderEntries).get()).length;

  Future<int> driveCount() async => (await db.select(db.drives).get()).length;

  setUp(() async {
    db = getTestDb();
    await addTestFilesToDb(
      db,
      driveId: driveId,
      rootFolderId: rootFolderId,
      nestedFolderId: nestedFolderId,
      emptyNestedFolderCount: 0,
      emptyNestedFolderIdPrefix: 'empty-',
      rootFolderFileCount: 1,
      nestedFolderFileCount: 1,
    );

    arweave = MockArweaveService();
    profile = MockProfileCubit();
    final wallet = getTestWallet();
    when(() => profile.state).thenReturn(
      ProfileLoggedIn(
        user: User(
          password: '123',
          wallet: wallet,
          walletAddress: await wallet.getAddress(),
          walletBalance: BigInt.from(100000000),
          cipherKey: SecretKey(List.filled(32, 1)),
          profileType: ProfileType.arConnect,
          errorFetchingIOTokens: false,
        ),
        useTurbo: false,
      ),
    );
  });

  tearDown(() => db.close());

  group('creating a drive', () {
    DriveCreateCubit build() {
      return DriveCreateCubit(
        arweave: arweave,
        turboUploadService: DontUseUploadService(),
        driveDao: db.driveDao,
        profileCubit: profile,
        drivesCubit: MockDrivesCubit(),
      );
    }

    blocTest<DriveCreateCubit, DriveCreateState>(
      'on another wallet, says so and creates nothing',
      setUp: walletIsElsewhere,
      build: build,
      act: (cubit) => cubit.submit('new drive'),
      expect: () => [isA<DriveCreateWalletMismatch>()],
      verify: (_) async {
        verifyZeroInteractions(arweave);
        expect(await driveCount(), 1);
      },
    );

    blocTest<DriveCreateCubit, DriveCreateState>(
      'Wander unavailable, then Cancel: creates nothing, the form stays',
      setUp: wanderUnavailable,
      build: build,
      act: (cubit) => cubit.submit('new drive'),
      expect: () => const <DriveCreateState>[],
      verify: (cubit) async {
        expect(cubit.state, isA<DriveCreateInitial>());
        verifyZeroInteractions(arweave);
        expect(await driveCount(), 1);
      },
    );
  });

  group('creating a folder', () {
    FolderCreateCubit build() => FolderCreateCubit(
          driveId: driveId,
          parentFolderId: rootFolderId,
          profileCubit: profile,
          arweave: arweave,
          turboUploadService: DontUseUploadService(),
          driveDao: db.driveDao,
        );

    blocTest<FolderCreateCubit, FolderCreateState>(
      'on another wallet, says so and creates nothing',
      setUp: walletIsElsewhere,
      build: build,
      act: (cubit) => cubit.submit(folderName: 'new folder'),
      expect: () => [isA<FolderCreateWalletMismatch>()],
      verify: (_) async {
        verifyZeroInteractions(arweave);
        expect(await folderCount(), 2);
      },
    );

    blocTest<FolderCreateCubit, FolderCreateState>(
      'Wander unavailable, then Cancel: creates nothing, ends in a failure',
      setUp: wanderUnavailable,
      build: build,
      act: (cubit) => cubit.submit(folderName: 'new folder'),
      expect: () => [isA<FolderCreateFailure>()],
      verify: (_) async {
        verifyZeroInteractions(arweave);
        expect(await folderCount(), 2);
      },
    );
  });

  group('renaming a drive', () {
    DriveRenameCubit build() => DriveRenameCubit(
          driveId: driveId,
          arweave: arweave,
          turboUploadService: DontUseUploadService(),
          driveDao: db.driveDao,
          profileCubit: profile,
          syncCubit: MockSyncBloc(),
        );

    Future<String> driveName() async =>
        (await db.driveDao.driveById(driveId: driveId).getSingle()).name;

    blocTest<DriveRenameCubit, DriveRenameState>(
      'on another wallet, says so and renames nothing',
      setUp: walletIsElsewhere,
      build: build,
      act: (cubit) => cubit.submit(newName: 'renamed'),
      expect: () => [isA<DriveRenameWalletMismatch>()],
      verify: (_) async {
        verifyZeroInteractions(arweave);
        expect(await driveName(), 'fake-drive-name');
      },
    );

    blocTest<DriveRenameCubit, DriveRenameState>(
      'Wander unavailable, then Cancel: renames nothing, ends in a failure',
      setUp: wanderUnavailable,
      build: build,
      act: (cubit) => cubit.submit(newName: 'renamed'),
      expect: () => [isA<DriveRenameFailure>()],
      verify: (_) async {
        verifyZeroInteractions(arweave);
        expect(await driveName(), 'fake-drive-name');
      },
    );
  });

  group('renaming a folder', () {
    FsEntryRenameCubit build() => FsEntryRenameCubit(
          driveId: driveId,
          folderId: nestedFolderId,
          arweave: arweave,
          turboUploadService: DontUseUploadService(),
          driveDao: db.driveDao,
          profileCubit: profile,
          crypto: MockArDriveCrypto(),
        );

    Future<String> folderName() async =>
        (await db.driveDao.folderById(folderId: nestedFolderId).getSingle())
            .name;

    blocTest<FsEntryRenameCubit, FsEntryRenameState>(
      'on another wallet, says so and renames nothing',
      setUp: walletIsElsewhere,
      build: build,
      act: (cubit) => cubit.submit(newName: 'renamed'),
      expect: () => [isA<FolderEntryRenameWalletMismatch>()],
      verify: (_) async {
        verifyZeroInteractions(arweave);
        expect(await folderName(), nestedFolderId);
      },
    );

    blocTest<FsEntryRenameCubit, FsEntryRenameState>(
      'Wander unavailable, then Cancel: renames nothing, ends in a failure',
      setUp: wanderUnavailable,
      build: build,
      act: (cubit) => cubit.submit(newName: 'renamed'),
      expect: () => [isA<FolderEntryRenameFailure>()],
      verify: (_) async {
        verifyZeroInteractions(arweave);
        expect(await folderName(), nestedFolderId);
      },
    );
  });

  group('repairing a ghost folder', () {
    Future<GhostFixerCubit> loaded() async {
      final ghost = DriveDataTableItemMapper.fromFolderEntry(
        await db.driveDao.folderById(folderId: nestedFolderId).getSingle(),
        0,
        true,
      );
      final cubit = GhostFixerCubit(
        ghostFolder: ghost,
        profileCubit: profile,
        arweave: arweave,
        turboUploadService: DontUseUploadService(),
        driveDao: db.driveDao,
      );
      await cubit.stream.firstWhere((s) => s is GhostFixerFolderLoadSuccess);
      return cubit;
    }

    Future<List<GhostFixerState>> submit(GhostFixerCubit cubit) async {
      final states = <GhostFixerState>[];
      final sub = cubit.stream.listen(states.add);
      await cubit.submit('repaired');
      await pumpEventQueue();
      await sub.cancel();
      await cubit.close();
      return states;
    }

    test('on another wallet, says so and repairs nothing', () async {
      walletIsElsewhere();
      final states = await submit(await loaded());

      expect(states, [isA<GhostFixerWalletMismatch>()]);
      verifyZeroInteractions(arweave);
    });

    test('Wander unavailable, then Cancel: repairs nothing, ends in a failure',
        () async {
      wanderUnavailable();
      final states = await submit(await loaded());

      expect(states, [isA<GhostFixerFailure>()]);
      verifyZeroInteractions(arweave);
    });
  });
}
