import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/user/user.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

class _MockProfile extends MockCubit<ProfileState> implements ProfileCubit {}

/// A name that is taken is reported every time it is tried: the conflict state
/// has no props, so an equal one is dropped by the cubit and the second try
/// would say nothing.
void main() {
  late _MockProfile profile;
  late MockDriveDao driveDao;

  FolderCreateCubit build() => FolderCreateCubit(
        driveId: 'drive',
        parentFolderId: 'folder',
        profileCubit: profile,
        arweave: MockArweaveService(),
        turboUploadService: MockTurboUploadService(),
        driveDao: driveDao,
      );

  setUp(() {
    profile = _MockProfile();
    when(() => profile.state).thenReturn(
      ProfileLoggedIn(
        user: User(
          password: 'password',
          wallet: getTestWallet(),
          walletAddress: 'address',
          walletBalance: BigInt.one,
          cipherKey: SecretKey(List.filled(32, 7)),
          profileType: ProfileType.json,
          errorFetchingIOTokens: false,
        ),
        useTurbo: false,
      ),
    );
    when(() => profile.logoutIfWalletMismatch()).thenAnswer((_) async => false);
    driveDao = MockDriveDao();
    when(() => driveDao.doesEntityWithNameExist(
          name: any(named: 'name'),
          driveId: any(named: 'driveId'),
          parentFolderId: any(named: 'parentFolderId'),
        )).thenAnswer((_) async => true);
  });

  blocTest<FolderCreateCubit, FolderCreateState>(
    'the same taken name tried twice is reported twice',
    build: build,
    act: (cubit) async {
      await cubit.submit(folderName: 'Receipts');
      await cubit.submit(folderName: 'Receipts');
    },
    expect: () => [
      isA<FolderCreateNameAlreadyExists>(),
      isA<FolderCreateInitial>(),
      isA<FolderCreateNameAlreadyExists>(),
      isA<FolderCreateInitial>(),
    ],
  );

  blocTest<FolderCreateCubit, FolderCreateState>(
    'a second taken name is reported with its own name',
    build: build,
    act: (cubit) async {
      await cubit.submit(folderName: 'Receipts');
      await cubit.submit(folderName: 'Invoices');
    },
    expect: () => [
      isA<FolderCreateNameAlreadyExists>()
          .having((s) => s.folderName, 'name', 'Receipts'),
      isA<FolderCreateInitial>(),
      isA<FolderCreateNameAlreadyExists>()
          .having((s) => s.folderName, 'name', 'Invoices'),
      isA<FolderCreateInitial>(),
    ],
  );
}
