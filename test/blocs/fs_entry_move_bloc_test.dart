import 'dart:typed_data';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

void main() {
//generate tests for FsEntryMoveBloc class
  group('FsEntryMoveBloc', () {
    late Database db;
    late DriveDao driveDao;
    late ArweaveService arweave;

    late ProfileCubit profileCubit;
    late SyncCubit syncBloc;
    const mockDriveId = 'mock-drive-id';
    const mockRootFolderId = 'mock-root-folder-id';
    const mockNestedFolderId = 'mock-nested-folder-id';
    const mockEmptyNestedFolderIdPrefix = 'mock-empty-nested-folder-id-prefix';
    const mockEmptyNestedFolderCount = 3;
    const mockRootFolderFileCount = 3;
    const mockNestedFolderFileCount = 3;

    setUp(() async {
      db = getTestDb();
      addTestFilesToDb(
        db,
        driveId: mockDriveId,
        rootFolderId: mockRootFolderId,
        nestedFolderId: mockNestedFolderId,
        emptyNestedFolderCount: mockEmptyNestedFolderCount,
        emptyNestedFolderIdPrefix: mockEmptyNestedFolderIdPrefix,
        rootFolderFileCount: mockRootFolderFileCount,
        nestedFolderFileCount: mockNestedFolderFileCount,
      );
      driveDao = db.driveDao;
      arweave = MockArweaveService();
      syncBloc = MockSyncBloc();

      profileCubit = MockProfileCubit();

      final keyBytes = Uint8List(32);
      fillBytesWithSecureRandom(keyBytes);
      final wallet = getTestWallet();
      when(() => profileCubit.state).thenReturn(
        ProfileLoggedIn(
          username: '',
          password: '123',
          wallet: wallet,
          cipherKey: SecretKey(keyBytes),
          walletAddress: await wallet.getAddress(),
          walletBalance: BigInt.one,
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });
    blocTest(
      'throws when selectedItems is empty',
      build: () => FsEntryMoveBloc(
        arweave: arweave,
        syncCubit: syncBloc,
        driveId: mockDriveId,
        driveDao: driveDao,
        profileCubit: profileCubit,
        selectedItems: [],
      ),
      errors: () => [isA<Exception>()],
    );
  });
}
