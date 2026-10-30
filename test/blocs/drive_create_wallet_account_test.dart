import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart'
    show DrivePrivacy;
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/locked_drives/domain/drive_unlock_session.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/locked_drives/domain/locked_drive.dart';
import 'package:ardrive/models/models.dart' show Drive;
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/upload_entry/presentation/first_upload.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_utils/ardrive_utils.dart' show DrivePrivacyTag;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

class _MockDriveUnlocker extends Mock implements DriveUnlocker {}

class _FakeDriveTx extends Fake implements TransactionCommonMixin {}

const _strong = 'Velvet harbour 47 lanterns drift';

/// One drive password for all private drives, for an account that signed
/// in with a browser wallet and so typed none: its first private drive sets
/// it, later ones use it, and with private drives already it is entered and
/// checked. Never a choice per drive.
void main() {
  late MockDriveDao driveDao;
  late MockProfileCubit profileCubit;
  late MockDrivesCubit drivesCubit;
  late DriveUnlockSession session;
  late _MockDriveUnlocker unlocker;
  late String address;
  late MockArweaveService arweave;

  setUpAll(() {
    registerFallbackValue(getTestWallet());
    registerFallbackValue(SecretKey([0]));
  });

  void signedInWith(String password) =>
      when(() => profileCubit.state).thenReturn(ProfileLoggedIn(
        user: User(
          password: password,
          wallet: getTestWallet(),
          walletAddress: address,
          walletBalance: BigInt.from(10000001),
          cipherKey: SecretKey([1, 2, 3]),
          profileType: ProfileType.arConnect,
          errorFetchingIOTokens: false,
        ),
        useTurbo: false,
      ));

  void drives({List<Drive> userDrives = const []}) =>
      when(() => drivesCubit.state).thenReturn(DrivesLoadSuccess(
        selectedDriveId: null,
        userDrives: userDrives,
        sharedDrives: const [],
        drivesWithAlerts: const [],
        canCreateNewDrive: true,
      ));

  setUp(() async {
    address = await getTestWallet().getAddress();
    driveDao = MockDriveDao();
    profileCubit = MockProfileCubit();
    drivesCubit = MockDrivesCubit();
    session = DriveUnlockSession();
    unlocker = _MockDriveUnlocker();
    arweave = MockArweaveService();
    // Arweave has no private drive of theirs unless a test says so.
    when(() => arweave.getFirstPrivateDriveTx(any(),
        maxRetries: any(named: 'maxRetries'))).thenAnswer((_) async => null);
    when(() => unlocker.session).thenReturn(session);
    when(() => profileCubit.logoutIfWalletMismatch())
        .thenAnswer((_) async => false);
    signedInWith('');
    drives();
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

  DriveCreateCubit cubit({DrivePrivacy privacy = DrivePrivacy.private}) =>
      DriveCreateCubit(
        arweave: arweave,
        turboUploadService: DontUseUploadService(),
        driveDao: driveDao,
        profileCubit: profileCubit,
        drivesCubit: drivesCubit,
        privacy: privacy,
        driveUnlocker: unlocker,
      );

  List<String> passwordsUsed() => verify(() => driveDao.createDrive(
        name: any(named: 'name'),
        ownerAddress: any(named: 'ownerAddress'),
        privacy: any(named: 'privacy'),
        wallet: any(named: 'wallet'),
        password: captureAny(named: 'password'),
        signatureType: any(named: 'signatureType'),
        profileKey: any(named: 'profileKey'),
      )).captured.cast<String>();

  void neverCreated() => verifyNever(() => driveDao.createDrive(
        name: any(named: 'name'),
        ownerAddress: any(named: 'ownerAddress'),
        privacy: any(named: 'privacy'),
        wallet: any(named: 'wallet'),
        password: any(named: 'password'),
        signatureType: any(named: 'signatureType'),
        profileKey: any(named: 'profileKey'),
      ));

  Drive privateDrive(String id) => Drive(
        id: id,
        rootFolderId: 'root-$id',
        ownerAddress: address,
        name: id,
        privacy: DrivePrivacyTag.private,
        dateCreated: DateTime(2025),
        lastUpdated: DateTime(2025),
        isHidden: false,
      );

  group('a browser wallet account', () {
    test(
        'with no private drive sets the drive password, and every later '
        'private drive uses it', () async {
      final first = cubit();
      expect(first.drivePasswordAsk, DrivePasswordAsk.set);
      expect(await first.confirmDrivePasswordAsk(), DrivePasswordAsk.set);

      await first.submit('Photos', newDrivePassword: _strong);
      expect(session.newDrivePassword(address), _strong);

      final second = cubit();
      expect(second.drivePasswordAsk, isNull,
          reason: 'never asked again this session, never per drive');
      await second.submit('Work');

      expect(passwordsUsed(), [_strong, _strong]);
    });

    test(
        'a drive password that breaks the new-account rules is refused, '
        'and nothing is made', () async {
      final create = cubit();
      await create.confirmDrivePasswordAsk();

      await expectLater(create.submit('Photos', newDrivePassword: 'short'),
          throwsArgumentError);
      await expectLater(create.submit('Photos'), throwsArgumentError);

      neverCreated();
      expect(session.newDrivePassword(address), isNull);
    });

    test(
        'a private drive the local list doesn\'t show yet, found on Arweave: '
        'the drive password is entered, never set', () async {
      when(() => arweave.getFirstPrivateDriveTx(any(),
              maxRetries: any(named: 'maxRetries')))
          .thenAnswer((_) async => _FakeDriveTx());
      final create = cubit();
      expect(create.drivePasswordAsk, DrivePasswordAsk.set);

      expect(await create.confirmDrivePasswordAsk(), DrivePasswordAsk.enter);
      expect(create.drivePasswordAsk, DrivePasswordAsk.enter);
      await expectLater(create.submit('Photos', newDrivePassword: _strong),
          throwsArgumentError);
      neverCreated();
    });

    test('Arweave not answering counts as having drives: entered, not set',
        () async {
      when(() => arweave.getFirstPrivateDriveTx(any(),
              maxRetries: any(named: 'maxRetries')))
          .thenThrow(Exception('gateway down'));
      final create = cubit();

      expect(await create.confirmDrivePasswordAsk(), DrivePasswordAsk.enter);
    });

    test('a password is never set before Arweave is asked', () async {
      final create = cubit();

      await expectLater(
          create.submit('Photos', newDrivePassword: _strong), throwsStateError);
      neverCreated();
    });

    test('with a private drive enters the drive password, checked on it',
        () async {
      drives(userDrives: [privateDrive('old')]);
      when(() => unlocker.verifyDrivePassword(
            wallet: any(named: 'wallet'),
            profileKey: any(named: 'profileKey'),
            password: any(named: 'password'),
            knownPrivateDriveIds: any(named: 'knownPrivateDriveIds'),
          )).thenAnswer((_) async => null);
      final create = cubit();
      expect(create.drivePasswordAsk, DrivePasswordAsk.enter);

      await create.submit('New', drivePassword: 'their password');

      expect(passwordsUsed(), ['their password']);
    });

    test('with only a locked drive enters it too', () {
      session.setLockedDrives(address, [
        LockedDrive(
          driveId: 'locked',
          ownerAddress: address,
          signatureType: DriveSignatureType.v2,
          lastUpdated: DateTime(2025),
        ),
      ]);

      expect(cubit().drivePasswordAsk, DrivePasswordAsk.enter);
    });

    test('before the drive list is known, checks rather than sets', () {
      when(() => drivesCubit.state).thenReturn(DrivesLoadInProgress());

      expect(cubit().drivePasswordAsk, DrivePasswordAsk.enter);
    });

    test('a public drive asks nothing', () {
      expect(cubit(privacy: DrivePrivacy.public).drivePasswordAsk, isNull);
    });
  });

  test(
      'a keyfile, phrase or generated account uses its password: nothing '
      'is asked', () async {
    signedInWith('sign-in password');
    final create = cubit();

    expect(create.drivePasswordAsk, isNull);
    await create.submit('Photos');
    expect(passwordsUsed(), ['sign-in password']);
  });

  group('the first upload', () {
    test('makes a private drive, never a public one', () {
      final create = firstDriveCubit(
        arweave: arweave,
        turboUploadService: DontUseUploadService(),
        driveDao: driveDao,
        profileCubit: profileCubit,
        drivesCubit: drivesCubit,
        driveUnlocker: unlocker,
      );

      expect(create.privacy, DrivePrivacy.private);
      expect(create.state.privacy, DrivePrivacy.private);
      expect(create.form.control('privacy').value, DrivePrivacy.private.name);
    });

    test(
        'a private drive found on Arweave: no password is set, Create '
        'drive checks it', () async {
      when(() => arweave.getFirstPrivateDriveTx(any(),
              maxRetries: any(named: 'maxRetries')))
          .thenAnswer((_) async => _FakeDriveTx());
      var asked = 0;

      final outcome = await makeFirstPrivateDrive(
        cubit: cubit(),
        askNewDrivePassword: () async {
          asked++;
          return _strong;
        },
      );

      expect(outcome, FirstUploadDrive.needsDrivePasswordChecked);
      expect(asked, 0);
      neverCreated();
    });

    test(
        'a browser wallet account sets the drive password, then a private '
        'My files is made with it', () async {
      var asked = 0;

      final outcome = await makeFirstPrivateDrive(
        cubit: cubit(),
        askNewDrivePassword: () async {
          asked++;
          return _strong;
        },
      );

      expect(asked, 1);
      // The mocked network stops it after the key.
      expect(outcome, FirstUploadDrive.failed);
      final name = verify(() => driveDao.createDrive(
            name: captureAny(named: 'name'),
            ownerAddress: any(named: 'ownerAddress'),
            privacy: captureAny(named: 'privacy'),
            wallet: any(named: 'wallet'),
            password: captureAny(named: 'password'),
            signatureType: any(named: 'signatureType'),
            profileKey: any(named: 'profileKey'),
          )).captured;
      expect(name, ['My files', DrivePrivacyTag.private, _strong]);
    });

    test('Cancel makes nothing', () async {
      final outcome = await makeFirstPrivateDrive(
        cubit: cubit(),
        askNewDrivePassword: () async => null,
      );

      expect(outcome, FirstUploadDrive.cancelled);
      neverCreated();
      expect(session.newDrivePassword(address), isNull);
    });

    test('an account with a password is asked nothing', () async {
      signedInWith('sign-in password');
      var asked = 0;

      await makeFirstPrivateDrive(
        cubit: cubit(),
        askNewDrivePassword: () async {
          asked++;
          return _strong;
        },
      );

      expect(asked, 0);
      expect(passwordsUsed(), ['sign-in password']);
    });

    test(
        'an account with private drives it hasn\'t opened goes to Create '
        'drive to check its password', () async {
      drives(userDrives: [privateDrive('old')]);

      final outcome = await makeFirstPrivateDrive(
        cubit: cubit(),
        askNewDrivePassword: () async => _strong,
      );

      expect(outcome, FirstUploadDrive.needsDrivePasswordChecked);
      neverCreated();
    });
  });
}
