import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/pages/no_drives/first_drive_page.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart'
    show DrivePrivacy;
import 'package:ardrive_utils/ardrive_utils.dart' show DrivePrivacyTag;
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart' show Drive;
import 'package:ardrive/locked_drives/data/sign_in_password_proof_store.dart';
import 'package:ardrive/locked_drives/domain/drive_unlock_session.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/locked_drives/presentation/unlock_drive_cubit.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/user.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/locked_drive_fixtures.dart';
import '../test_utils/utils.dart';

class _MockDriveUnlocker extends Mock implements DriveUnlocker {}

/// There is one drive password for all of a user's private drives, and
/// normally the sign-in password is it. After a sign-in whose password opened
/// none of the wallet's private drives - possibly a typo the user continued
/// past - a new private drive asks for the drive password, and checks it by
/// opening one of their existing drives, rather than locking itself with
/// something the user may not know.
void main() {
  late MockDriveDao driveDao;
  late MockProfileCubit profileCubit;
  late MockDrivesCubit drivesCubit;
  late DriveUnlockSession session;
  late _MockDriveUnlocker unlocker;
  late MemoryKeyValueStore store;
  late SignInPasswordProofStore proofStore;
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
    drivesCubit = MockDrivesCubit();
    session = DriveUnlockSession();
    unlocker = _MockDriveUnlocker();
    store = MemoryKeyValueStore();
    proofStore = SignInPasswordProofStore(store: () async => store);

    when(() => unlocker.session).thenReturn(session);
    when(() => drivesCubit.state).thenReturn(DrivesLoadInProgress());
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

  void passwordOpens(DriveUnlockFailure? verdict) =>
      when(() => unlocker.verifyDrivePassword(
            wallet: any(named: 'wallet'),
            profileKey: any(named: 'profileKey'),
            password: any(named: 'password'),
            knownPrivateDriveIds: any(named: 'knownPrivateDriveIds'),
          )).thenAnswer((_) async => verdict);

  DriveCreateCubit cubit({
    DrivePrivacy privacy = DrivePrivacy.private,
    bool withUnlocker = true,
  }) =>
      DriveCreateCubit(
        arweave: MockArweaveService(),
        turboUploadService: DontUseUploadService(),
        driveDao: driveDao,
        profileCubit: profileCubit,
        drivesCubit: drivesCubit,
        privacy: privacy,
        driveUnlocker: withUnlocker ? unlocker : null,
        proofStore: proofStore,
      );

  String passwordUsed() => verify(() => driveDao.createDrive(
        name: any(named: 'name'),
        ownerAddress: any(named: 'ownerAddress'),
        privacy: any(named: 'privacy'),
        wallet: any(named: 'wallet'),
        password: captureAny(named: 'password'),
        signatureType: any(named: 'signatureType'),
        profileKey: any(named: 'profileKey'),
      )).captured.last as String;

  void neverCreated() => verifyNever(() => driveDao.createDrive(
        name: any(named: 'name'),
        ownerAddress: any(named: 'ownerAddress'),
        privacy: any(named: 'privacy'),
        wallet: any(named: 'wallet'),
        password: any(named: 'password'),
        signatureType: any(named: 'signatureType'),
        profileKey: any(named: 'profileKey'),
      ));

  test(
      'after an unproven sign-in password, the drive password is checked on '
      'an existing drive, then the drive is made with it, and the session '
      'does not ask again', () async {
    session.setSignInPasswordProven(address, false);
    passwordOpens(null);
    final create = cubit();

    expect(create.needsDrivePassword, isTrue);
    await expectLater(create.submit('Drive'), throwsArgumentError);

    await create.submit('Drive', drivePassword: 'drive password');
    verify(() => unlocker.verifyDrivePassword(
          wallet: any(named: 'wallet'),
          profileKey: any(named: 'profileKey'),
          password: 'drive password',
          knownPrivateDriveIds: any(named: 'knownPrivateDriveIds'),
        )).called(1);
    expect(passwordUsed(), 'drive password');
    await create.close();

    final next = cubit();
    expect(next.needsDrivePassword, isFalse);
    await next.submit('Another');
    expect(passwordUsed(), 'drive password');
    await next.close();
  });

  test(
      'a drive password that opens none of their drives makes nothing, '
      'and says so', () async {
    session.setSignInPasswordProven(address, false);
    passwordOpens(DriveUnlockFailure.wrongPassword);
    final create = cubit();

    await create.submit('Drive', drivePassword: 'typo');

    expect(
      create.state,
      const DriveCreateDrivePasswordRejected(
          privacy: DrivePrivacy.private,
          reason: DriveUnlockFailure.wrongPassword),
    );
    neverCreated();
    expect(session.newDrivePassword(address), isNull);
    expect(create.needsDrivePassword, isTrue);
    await create.close();
  });

  test('a cancelled wallet prompt returns quietly and makes nothing', () async {
    session.setSignInPasswordProven(address, false);
    passwordOpens(DriveUnlockFailure.walletDeclined);
    final create = cubit();

    await create.submit('Drive', drivePassword: 'drive password');

    expect(create.state, isA<DriveCreateInitial>());
    neverCreated();
    await create.close();
  });

  test(
      'the sign-in password, once it opens a drive here, is proven: in the '
      'session and on this device', () async {
    await proofStore.markUnproven(address);
    session.setSignInPasswordProven(address, false);
    passwordOpens(null);
    final create = cubit();

    await create.submit('Drive', drivePassword: 'sign-in password');

    expect(session.signInPasswordProven(address), isTrue);
    expect(await proofStore.isUnproven(address), isFalse);
    await create.close();
  });

  test('a proven sign-in password makes the key without any check', () async {
    session.setSignInPasswordProven(address, true);
    final create = cubit();

    expect(create.needsDrivePassword, isFalse);
    await create.submit('Drive');
    expect(passwordUsed(), 'sign-in password');
    verifyNever(() => unlocker.verifyDrivePassword(
          wallet: any(named: 'wallet'),
          profileKey: any(named: 'profileKey'),
          password: any(named: 'password'),
          knownPrivateDriveIds: any(named: 'knownPrivateDriveIds'),
        ));
    await create.close();
  });

  test(
      'a session that never checked, a public drive, and a cubit with no '
      'unlocker change nothing', () async {
    expect(cubit().needsDrivePassword, isFalse);

    session.setSignInPasswordProven(address, false);
    expect(cubit(privacy: DrivePrivacy.public).needsDrivePassword, isFalse);
    expect(cubit(withUnlocker: false).needsDrivePassword, isFalse);
  });

  test('the drive password is checked on their private drives, oldest first',
      () async {
    session.setSignInPasswordProven(address, false);
    passwordOpens(DriveUnlockFailure.wrongPassword);
    Drive drive(String id, int year, String privacy) => Drive(
          id: id,
          rootFolderId: 'root',
          ownerAddress: address,
          name: id,
          lastUpdated: DateTime(year),
          dateCreated: DateTime(year),
          privacy: privacy,
          isHidden: false,
        );
    when(() => drivesCubit.state).thenReturn(DrivesLoadSuccess(
      selectedDriveId: 'newer',
      userDrives: [
        drive('newer', 2026, DrivePrivacyTag.private),
        drive('public', 2020, DrivePrivacyTag.public),
        drive('older', 2023, DrivePrivacyTag.private),
      ],
      sharedDrives: const [],
      drivesWithAlerts: const [],
      canCreateNewDrive: true,
    ));
    final create = cubit();

    await create.submit('Drive', drivePassword: 'typo');

    verify(() => unlocker.verifyDrivePassword(
          wallet: any(named: 'wallet'),
          profileKey: any(named: 'profileKey'),
          password: 'typo',
          knownPrivateDriveIds: ['older', 'newer'],
        )).called(1);
    await create.close();
  });

  test(
      '"My files" is never keyed with an unproven password: it is not made, '
      'and the wallet is not asked', () async {
    session.setSignInPasswordProven(address, false);

    expect(await makeMyFiles(cubit()), FirstDriveOutcome.failed);

    neverCreated();
    verifyNever(() => unlocker.verifyDrivePassword(
          wallet: any(named: 'wallet'),
          profileKey: any(named: 'profileKey'),
          password: any(named: 'password'),
          knownPrivateDriveIds: any(named: 'knownPrivateDriveIds'),
        ));
  });

  test('"My files" with a proven password is made with it', () async {
    session.setSignInPasswordProven(address, true);

    await makeMyFiles(cubit());

    expect(passwordUsed(), 'sign-in password');
  });

  group('after an Unlock', () {
    setUp(() {
      when(() => unlocker.unlock(
            wallet: any(named: 'wallet'),
            profileKey: any(named: 'profileKey'),
            driveId: any(named: 'driveId'),
            password: any(named: 'password'),
            tryOthers: any(named: 'tryOthers'),
          )).thenAnswer((_) async => const DriveUnlockResult.opened(['old']));
    });

    Future<void> unlockWith(String password) => UnlockDriveCubit(
          driveId: 'old',
          unlocker: unlocker,
          wallet: getTestWallet(),
          profileKey: null,
          syncDrives: (_) async {},
          signInPassword: 'sign-in password',
          proofStore: proofStore,
        ).submit(password: password, tryOthers: false);

    test(
        'an Unlock with another password while the sign-in one is unproven: '
        'Create still asks for the drive password, and never uses that one',
        () async {
      session.setSignInPasswordProven(address, false);
      passwordOpens(null);

      await unlockWith('Q2');
      final create = cubit();

      expect(create.needsDrivePassword, isTrue);
      await expectLater(create.submit('Drive'), throwsArgumentError);
      await create.submit('Drive', drivePassword: 'drive password');
      expect(passwordUsed(), 'drive password');
      await create.close();
    });

    test(
        'a later Unlock with the sign-in password proves it, and Create uses '
        'it again over the drive password typed earlier', () async {
      session.setSignInPasswordProven(address, false);
      passwordOpens(null);
      final first = cubit();
      await first.submit('Drive', drivePassword: 'drive password');
      expect(passwordUsed(), 'drive password');
      await first.close();

      await unlockWith('sign-in password');
      final next = cubit();

      expect(next.needsDrivePassword, isFalse);
      await next.submit('Another');
      expect(passwordUsed(), 'sign-in password');
      await next.close();
    });
  });
}
