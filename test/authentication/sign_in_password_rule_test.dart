import 'dart:convert';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/core/crypto/crypto.dart';
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
    when(() => arweave.getUniqueUserDriveEntityTxs(any(),
            maxRetries: any(named: 'maxRetries')))
        .thenAnswer((_) async => [for (final drive in drives) drive.tx]);
    for (final drive in drives) {
      when(() => arweave.getEntityDataBytes(drive.tx.id,
              configuredGatewayOnly: any(named: 'configuredGatewayOnly')))
          .thenAnswer((_) async => drive.data);
    }
  }

  setUpAll(() => registerFallbackValue(getTestWallet()));

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
      'a password that opens none of the wallet\'s private drives is still '
      '"Wrong password"', () async {
    onChain([
      await makeWebPrivateDrive(wallet: wallet, driveId: _first, password: 'a'),
      await makeWebPrivateDrive(
          wallet: wallet, driveId: _second, password: 'b'),
    ]);

    await expectLater(auth.validateUser(wallet, 'typo'),
        throwsA(isA<WrongPasswordException>()));
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

  test('a cancelled wallet prompt is "Wrong password", as it always was',
      () async {
    onChain([
      await makeWebPrivateDrive(wallet: wallet, driveId: _first, password: 'a'),
    ]);
    signer.refuse = true;

    await expectLater(
        auth.validateUser(wallet, 'a'), throwsA(isA<WrongPasswordException>()));
  });
}
