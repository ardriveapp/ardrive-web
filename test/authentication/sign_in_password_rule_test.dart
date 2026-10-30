import 'dart:convert';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/user/user.dart';
import 'package:cryptography/cryptography.dart';
import 'package:ardrive/locked_drives/domain/drive_unlock_session.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/locked_drive_fixtures.dart';
import '../test_utils/utils.dart';

const _first = '6939b9e0-cc98-42cb-bae0-5888eca78885';
const _second = '2c1d4b5e-0f3a-4c8b-9d7e-6a5b4c3d2e1f';

/// The sign-in password rule, against real drive keys: accepted if it opens
/// any private drive the wallet owns, or the wallet has none; "Wrong
/// password" if it has some and opens none.
void main() {
  late SignatureCounter signer;
  late Wallet wallet;
  late MockArweaveService arweave;
  late ArDriveAuthImpl auth;

  void onChain(List<PrivateDriveFixture> drives) {
    when(() => arweave.cachedUserDriveCreationTimes(any())).thenReturn({});
    when(() => arweave.getUniqueUserDriveEntityTxs(any(),
            maxRetries: any(named: 'maxRetries')))
        .thenAnswer((_) async => [for (final drive in drives) drive.tx]);
    for (final drive in drives) {
      when(() => arweave.getEntityDataBytes(drive.tx.id,
              configuredGatewayOnly: any(named: 'configuredGatewayOnly')))
          .thenAnswer((_) async => drive.data);
    }
  }

  setUpAll(() {
    registerFallbackValue(getTestWallet());
    registerFallbackValue(ProfileType.json);
  });

  setUp(() {
    signer = SignatureCounter(json.decode(getWalletString));
    wallet = signer.wallet;
    arweave = MockArweaveService();
    auth = ArDriveAuthImpl(
      arweave: arweave,
      userRepository: MockUserRepository(),
      crypto: ArDriveCrypto(),
      biometricAuthentication: MockBiometricAuthentication(),
      secureKeyValueStore: MockSecureKeyValueStore(),
      arConnectService: MockArConnectService(),
      databaseHelpers: MockDatabaseHelpers(),
      driveUnlocker: DriveUnlocker(
        crypto: ArDriveCrypto(),
        arweave: arweave,
        driveDao: MockDriveDao(),
        session: DriveUnlockSession(),
      ),
    );
  });

  test('a wallet with no private drives signs in with any password', () async {
    onChain([]);

    await auth.validateUser(wallet, 'anything');

    expect(signer.signatures, 0);
  });

  test(
      'a wallet whose first private drive has another password signs in '
      'with the password of a later one', () async {
    onChain([
      await makeWebPrivateDrive(
          wallet: wallet, driveId: _first, password: 'cli password'),
      await makeWebPrivateDrive(
          wallet: wallet, driveId: _second, password: 'login password'),
    ]);

    await auth.validateUser(wallet, 'login password');
  });

  test(
      'a password that opens none of the wallet\'s private drives asks the '
      'user to try again or continue, rather than signing in silently',
      () async {
    onChain([
      await makeWebPrivateDrive(wallet: wallet, driveId: _first, password: 'a'),
      await makeWebPrivateDrive(
          wallet: wallet, driveId: _second, password: 'b'),
    ]);

    await expectLater(auth.validateUser(wallet, 'typo'),
        throwsA(isA<PasswordOpensNoDriveException>()));
  });

  test(
      'a drive that can\'t be read is not a wrong password: with nothing '
      'opened, the gateway is reported', () async {
    final readable = await makeWebPrivateDrive(
        wallet: wallet, driveId: _first, password: 'a');
    final unreadable = await makeWebPrivateDrive(
        wallet: wallet, driveId: _second, password: 'b');
    onChain([readable, unreadable]);
    when(() => arweave.getEntityDataBytes(unreadable.tx.id,
            configuredGatewayOnly: any(named: 'configuredGatewayOnly')))
        .thenThrow(Exception('gateway down'));

    await expectLater(auth.validateUser(wallet, 'b'),
        throwsA(isA<AuthenticationGatewayException>()));
  });

  test('a cancelled wallet prompt opens nothing: try again or continue',
      () async {
    onChain([
      await makeWebPrivateDrive(wallet: wallet, driveId: _first, password: 'a'),
    ]);
    signer.refuse = true;

    await expectLater(auth.validateUser(wallet, 'a'),
        throwsA(isA<PasswordOpensNoDriveException>()));
  });

  test(
      'a cancelled wallet prompt ends the check at once: no second prompt '
      'for the next drive', () async {
    onChain([
      await makeWebPrivateDrive(wallet: wallet, driveId: _first, password: 'a'),
      await makeWebPrivateDrive(
          wallet: wallet, driveId: _second, password: 'a'),
    ]);
    signer
      ..signatures = 0
      ..refuse = true;

    await expectLater(auth.validateUser(wallet, 'a'),
        throwsA(isA<PasswordOpensNoDriveException>()));
    expect(signer.signatures, 1);
  });

  test(
      'a v1 drive whose signature record can\'t be read is a gateway error, '
      'not "Wrong password"', () async {
    final drive = await makeWebPrivateDrive(
        wallet: wallet,
        driveId: _first,
        password: 'a',
        signatureType: DriveSignatureType.v1);
    onChain([drive]);
    when(() => arweave.getDriveSignatureForDrive(any(), _first))
        .thenThrow(Exception('gateway down'));

    await expectLater(auth.validateUser(wallet, 'a'),
        throwsA(isA<AuthenticationGatewayException>()));
  });

  group('how much one sign-in may ask', () {
    String id(int i) =>
        '00000000-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}';

    /// [count] private drives, oldest first, all with [password].
    Future<void> drivesWith(int count, String password) async => onChain([
          for (var i = 0; i < count; i++)
            await makeWebPrivateDrive(
              wallet: wallet,
              driveId: id(i),
              password: password,
              unixTime: 1700000000 + i,
            ),
        ]);

    for (final count in [5, 20]) {
      test(
          'Wander, $count drives: a typo costs at most 3 prompts, and the '
          'right password then costs none', () async {
        await drivesWith(count, 'right');
        final wander = FakeWander(wallet);

        await expectLater(auth.validateUser(wander.wallet, 'typo'),
            throwsA(isA<PasswordOpensNoDriveException>()));
        expect(wander.prompts, 3);

        await auth.validateUser(wander.wallet, 'right');
        expect(wander.prompts, 3, reason: 'held signatures are tried first');
      });
    }

    test(
        'Wander: the oldest drive is tried first, and the first that opens '
        'ends it', () async {
      onChain([
        await makeWebPrivateDrive(
            wallet: wallet,
            driveId: id(2),
            password: 'b',
            unixTime: 1700000002),
        await makeWebPrivateDrive(
            wallet: wallet,
            driveId: id(1),
            password: 'b',
            unixTime: 1700000001),
        await makeWebPrivateDrive(
            wallet: wallet,
            driveId: id(0),
            password: 'a',
            unixTime: 1700000000),
      ]);
      final wander = FakeWander(wallet);

      await auth.validateUser(wander.wallet, 'a');

      expect(wander.prompts, 1);
    });

    test(
        'a local wallet, 20 drives: no prompt cap, every drive tried, and '
        'the right password then signs nothing new', () async {
      await drivesWith(20, 'right');
      signer.signatures = 0;

      await expectLater(auth.validateUser(wallet, 'typo'),
          throwsA(isA<PasswordOpensNoDriveException>()));
      expect(signer.signatures, 20);

      await auth.validateUser(wallet, 'right');
      expect(signer.signatures, 20);
    });

    test('a local wallet tries at most 20 drives', () async {
      await drivesWith(25, 'right');
      signer.signatures = 0;

      await expectLater(auth.validateUser(wallet, 'typo'),
          throwsA(isA<PasswordOpensNoDriveException>()));
      expect(signer.signatures, ArDriveAuthImpl.signInMaxDrives);
    });
  });

  test(
      'continuing signs in without trying any drive: the drives the password '
      'didn\'t open stay locked, and the wallet is not asked again', () async {
    onChain([
      await makeWebPrivateDrive(wallet: wallet, driveId: _first, password: 'a'),
    ]);
    final userRepository = MockUserRepository();
    final biometrics = MockBiometricAuthentication();
    when(() => biometrics.isEnabled()).thenAnswer((_) async => false);
    when(() => userRepository.hasUser()).thenAnswer((_) async => false);
    when(() => userRepository.saveUser(any(), any(), any(),
            sourceWalletAddress: any(named: 'sourceWalletAddress')))
        .thenAnswer((_) async {});
    when(() => userRepository.getUser(any())).thenAnswer((_) async => User(
          password: 'typo',
          wallet: wallet,
          walletAddress: 'address',
          walletBalance: BigInt.zero,
          cipherKey: SecretKey([1]),
          profileType: ProfileType.json,
          errorFetchingIOTokens: false,
        ));
    when(() => userRepository.getBalance(any()))
        .thenAnswer((_) async => BigInt.zero);
    when(() => userRepository.getARIOTokens(any()))
        .thenAnswer((_) async => '0');
    final auth = ArDriveAuthImpl(
      arweave: arweave,
      userRepository: userRepository,
      crypto: ArDriveCrypto(),
      biometricAuthentication: biometrics,
      secureKeyValueStore: MockSecureKeyValueStore(),
      arConnectService: MockArConnectService(),
      databaseHelpers: MockDatabaseHelpers(),
      driveUnlocker: DriveUnlocker(
        crypto: ArDriveCrypto(),
        arweave: arweave,
        driveDao: MockDriveDao(),
        session: DriveUnlockSession(),
      ),
    );
    signer.signatures = 0;

    await expectLater(auth.login(wallet, 'typo', ProfileType.json),
        throwsA(isA<PasswordOpensNoDriveException>()));
    final asked = signer.signatures;

    final user = await auth.login(wallet, 'typo', ProfileType.json,
        skipDriveCheck: true);

    expect(user.password, 'typo');
    expect(signer.signatures, asked, reason: 'continuing tried a drive again');
    verify(() => userRepository.saveUser('typo', ProfileType.json, wallet,
        sourceWalletAddress: any(named: 'sourceWalletAddress'))).called(1);
  });
}
