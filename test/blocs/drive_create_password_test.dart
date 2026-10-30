import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart'
    show DrivePrivacy;
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/locked_drives/domain/drive_unlock_session.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/user.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

/// A new private drive's key comes from a password. After a sign-in whose
/// password opened none of the wallet's private drives - possibly a typo the
/// user continued past - the drive asks for its own, rather than locking
/// itself with something the user may not know.
void main() {
  late MockDriveDao driveDao;
  late MockProfileCubit profileCubit;
  late DriveUnlockSession session;
  late String address;

  setUpAll(() {
    registerFallbackValue(getTestWallet());
    registerFallbackValue(SecretKey([0]));
  });

  setUp(() async {
    final wallet = getTestWallet();
    address = await wallet.getAddress();
    driveDao = MockDriveDao();
    profileCubit = MockProfileCubit();
    session = DriveUnlockSession();

    when(() => profileCubit.state).thenReturn(ProfileLoggedIn(
      user: User(
        password: 'sign-in password',
        wallet: wallet,
        walletAddress: address,
        walletBalance: BigInt.from(10000001),
        cipherKey: SecretKey([1, 2, 3]),
        profileType: ProfileType.json,
        errorFetchingIOTokens: false,
      ),
      useTurbo: false,
    ));
    when(() => profileCubit.logoutIfWalletMismatch())
        .thenAnswer((_) async => false);
    // Stops right after the key is made: the password it was made from is
    // all this test is about.
    when(() => driveDao.createDrive(
          name: any(named: 'name'),
          ownerAddress: any(named: 'ownerAddress'),
          privacy: any(named: 'privacy'),
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          signatureType: any(named: 'signatureType'),
          profileKey: any(named: 'profileKey'),
        )).thenThrow(Exception('stop here'));
  });

  DriveCreateCubit cubit({
    DrivePrivacy privacy = DrivePrivacy.private,
    DriveUnlockSession? unlockSession,
  }) =>
      DriveCreateCubit(
        arweave: MockArweaveService(),
        turboUploadService: DontUseUploadService(),
        driveDao: driveDao,
        profileCubit: profileCubit,
        drivesCubit: MockDrivesCubit(),
        privacy: privacy,
        unlockSession: unlockSession,
      );

  String passwordUsed() => verify(() => driveDao.createDrive(
        name: any(named: 'name'),
        ownerAddress: any(named: 'ownerAddress'),
        privacy: any(named: 'privacy'),
        wallet: any(named: 'wallet'),
        password: captureAny(named: 'password'),
        signatureType: any(named: 'signatureType'),
        profileKey: any(named: 'profileKey'),
      )).captured.single as String;

  test(
      'after an unproven sign-in password, a private drive takes its own '
      'password, and that is what its key is made from', () async {
    session.setSignInPasswordProven(address, false);
    final create = cubit(unlockSession: session);

    expect(create.needsDrivePassword, isTrue);
    await expectLater(create.submit('Drive'), throwsArgumentError);

    await create.submit('Drive', drivePassword: 'its own strong password');
    expect(passwordUsed(), 'its own strong password');
    await create.close();
  });

  test('a proven sign-in password makes the key, as it always has', () async {
    session.setSignInPasswordProven(address, true);
    final create = cubit(unlockSession: session);

    expect(create.needsDrivePassword, isFalse);
    await create.submit('Drive');
    expect(passwordUsed(), 'sign-in password');
    await create.close();
  });

  test(
      'a session that never checked (Welcome back), a public drive, and the '
      'first drive of a new account (no session) change nothing', () async {
    expect(cubit(unlockSession: session).needsDrivePassword, isFalse);

    session.setSignInPasswordProven(address, false);
    expect(
        cubit(privacy: DrivePrivacy.public, unlockSession: session)
            .needsDrivePassword,
        isFalse);
    expect(cubit().needsDrivePassword, isFalse);
  });
}
