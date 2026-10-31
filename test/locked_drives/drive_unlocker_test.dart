import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/locked_drives/domain/drive_password_info.dart';
import 'package:ardrive/locked_drives/domain/drive_unlock_session.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive/locked_drives/domain/locked_drive.dart';
import 'package:ardrive/locked_drives/domain/user_drive_discovery.dart';
import 'package:ardrive/models/models.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/locked_drive_fixtures.dart';
import '../test_utils/utils.dart';

const _driveA = '6939b9e0-cc98-42cb-bae0-5888eca78885';
const _driveB = '2c1d4b5e-0f3a-4c8b-9d7e-6a5b4c3d2e1f';
const _driveC = '9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d';
const _driveD = '3d4e5f6a-7b8c-4d9e-8f0a-1b2c3d4e5f6a';
const _driveE = '4e5f6a7b-8c9d-4e0f-9a1b-2c3d4e5f6a7b';

Future<List<int>> _bytes(DriveKey key) => key.key.extractBytes();

void main() {
  late SignatureCounter signer;
  late Wallet wallet;
  late String owner;
  late MockArweaveService arweave;
  late Database db;
  late DriveUnlockSession session;
  late DriveUnlocker unlocker;
  final profileKey = SecretKey(List.filled(32, 7));

  /// Answers the latest-metadata reads for [drives] as a gateway would.
  void onChain(List<PrivateDriveFixture> drives) {
    for (final drive in drives) {
      when(() => arweave.getLatestDriveTx(drive.driveId, owner,
              maxRetries: any(named: 'maxRetries')))
          .thenAnswer((_) async => drive.tx);
      when(() => arweave.getEntityDataBytes(drive.tx.id,
              configuredGatewayOnly: any(named: 'configuredGatewayOnly')))
          .thenAnswer((_) async => drive.data);
      when(() => arweave.getDriveSignatureForDrive(any(), drive.driveId))
          .thenAnswer((_) async => drive.record);
      when(() => arweave.getDriveSignatureForDriveOnSync(any(), drive.driveId))
          .thenAnswer((_) async => drive.record);
    }
  }

  LockedDrive locked(String driveId) => LockedDrive(
        driveId: driveId,
        ownerAddress: owner,
        signatureType: DriveSignatureType.v2,
        lastUpdated: DateTime(2026),
      );

  setUpAll(() {
    registerFallbackValue(getTestWallet());
  });

  setUp(() async {
    signer = SignatureCounter(json.decode(getWalletString));
    wallet = signer.wallet;
    owner = await wallet.getAddress();
    arweave = MockArweaveService();
    db = getTestDb();
    session = DriveUnlockSession();
    unlocker = DriveUnlocker(
      crypto: ArDriveCrypto(),
      arweave: arweave,
      driveDao: db.driveDao,
      session: session,
    );
  });

  tearDown(() => db.close());

  group('openWithKey', () {
    test('the right key opens the drive', () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'pw', name: 'Projects');

      final entity =
          await unlocker.openWithKey(drive.tx, drive.data, drive.key);

      expect(entity?.name, 'Projects');
      expect(entity?.id, _driveA);
    });

    test('a wrong key is null: AES-GCM authentication failed', () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'pw');

      expect(
        await unlocker.openWithKey(drive.tx, drive.data,
            DriveKey(SecretKey(List.filled(32, 1)), true)),
        isNull,
      );
    });

    test(
        'metadata that authenticates but is not a drive is unreadable, '
        'never a wrong password', () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'pw');
      final box = await ArDriveCrypto()
          .encrypt(Uint8List.fromList(utf8.encode('not json')), drive.key.key);
      final tx = FakeDriveTx(
        id: 'corrupt',
        ownerAddress: owner,
        tags: {
          for (final tag in drive.tx.tags)
            tag.name: tag.name == 'Cipher-IV'
                ? utils.encodeBytesToBase64(box.nonce)
                : tag.value,
        },
      );

      await expectLater(
        unlocker.openWithKey(
            tx, Uint8List.fromList(box.concatenation(nonce: false)), drive.key),
        throwsA(isA<DriveUnreadableException>()),
      );
    });
  });

  test(
      'an AES error that is not an authentication failure is unreadable, '
      'never a wrong password', () async {
    final drive = await makeWebPrivateDrive(
        wallet: wallet, driveId: _driveA, password: 'pw');

    // Too short to hold a GCM tag: not a wrong key, a broken entity.
    await expectLater(
      unlocker.openWithKey(drive.tx, Uint8List(5), drive.key),
      throwsA(isA<DriveUnreadableException>()),
    );
  });

  group('tryPassword', () {
    test('the right password opens a v2 drive and is remembered for it',
        () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'pw');

      final attempt = await unlocker.tryPassword(
          wallet: wallet, driveTx: drive.tx, data: drive.data, password: 'pw');

      expect(attempt.opened, isTrue);
      expect(await _bytes(attempt.key!), await _bytes(drive.key));
      expect(session.provenPasswordInfo(_driveA), utf8.encode('pw'));
    });

    test('a wrong password is wrongPassword, and nothing is remembered',
        () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'pw');

      final attempt = await unlocker.tryPassword(
          wallet: wallet, driveTx: drive.tx, data: drive.data, password: 'no');

      expect(attempt.failure, DriveUnlockFailure.wrongPassword);
      expect(session.provenPasswordInfo(_driveA), isNull);
    });

    test('the wallet signs once per drive, however many passwords are tried',
        () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'pw');
      signer.signatures = 0;

      for (final password in ['a', 'b', 'c', 'pw']) {
        await unlocker.tryPassword(
            wallet: wallet,
            driveTx: drive.tx,
            data: drive.data,
            password: password);
      }

      expect(signer.signatures, 1);
    });

    test(
        'a drive made by core-js with a non-ASCII password opens: the '
        'double-encoded form is tried after the plain one', () async {
      final drive = await makePrivateDrive(
        wallet: wallet,
        driveId: _driveA,
        passwordInfo: coreJsPasswordInfo('pässwörd ä'),
      );

      final attempt = await unlocker.tryPassword(
          wallet: wallet,
          driveTx: drive.tx,
          data: drive.data,
          password: 'pässwörd ä');

      expect(attempt.opened, isTrue);
      expect(attempt.passwordInfo, coreJsPasswordInfo('pässwörd ä'));
    });

    test('a web drive with a non-ASCII password opens with the plain form',
        () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'pässwörd ä');

      final attempt = await unlocker.tryPassword(
          wallet: wallet,
          driveTx: drive.tx,
          data: drive.data,
          password: 'pässwörd ä');

      expect(attempt.opened, isTrue);
      expect(attempt.passwordInfo, utf8.encode('pässwörd ä'));
    });

    test('a v1 drive with a stored signature opens with the right password',
        () async {
      final drive = await makeWebPrivateDrive(
        wallet: wallet,
        driveId: _driveA,
        password: 'pw',
        signatureType: DriveSignatureType.v1,
        withRecord: true,
      );
      onChain([drive]);

      final right = await unlocker.tryPassword(
          wallet: wallet, driveTx: drive.tx, data: drive.data, password: 'pw');
      final wrong = await unlocker.tryPassword(
          wallet: wallet, driveTx: drive.tx, data: drive.data, password: 'no');

      expect(right.opened, isTrue);
      expect(right.key!.generated, isFalse);
      expect(await _bytes(right.key!), await _bytes(drive.key));
      expect(wrong.failure, DriveUnlockFailure.wrongPassword);
    });

    test('a v1 drive whose signature record cannot be read is unavailable',
        () async {
      final drive = await makeWebPrivateDrive(
        wallet: wallet,
        driveId: _driveA,
        password: 'pw',
        signatureType: DriveSignatureType.v1,
      );
      when(() => arweave.getDriveSignatureForDrive(any(), _driveA))
          .thenThrow(Exception('gateway down'));

      final attempt = await unlocker.tryPassword(
          wallet: wallet, driveTx: drive.tx, data: drive.data, password: 'pw');

      expect(attempt.failure, DriveUnlockFailure.unavailable);
    });

    test(
        'a refused signature is walletDeclined, remembered, and not asked '
        'again by a pass that may not ask', () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'pw');
      signer
        ..signatures = 0
        ..refuse = true;

      final first = await unlocker.tryPassword(
          wallet: wallet, driveTx: drive.tx, data: drive.data, password: 'pw');
      final background = await unlocker.tryPassword(
          wallet: wallet,
          driveTx: drive.tx,
          data: drive.data,
          password: 'pw',
          mayAskWallet: false);

      expect(first.failure, DriveUnlockFailure.walletDeclined);
      expect(background.failure, DriveUnlockFailure.walletDeclined);
      expect(session.walletDeclined(owner, _driveA), isTrue);
      expect(signer.signatures, 1);
    });
  });

  test(
      'a core-js v1 drive with a stored signature and a non-ASCII password '
      'opens through the double encoding', () async {
    final drive = await makePrivateDrive(
      wallet: wallet,
      driveId: _driveA,
      passwordInfo: coreJsPasswordInfo('pässwörd ä'),
      signatureType: DriveSignatureType.v1,
      withRecord: true,
    );
    onChain([drive]);

    final attempt = await unlocker.tryPassword(
        wallet: wallet,
        driveTx: drive.tx,
        data: drive.data,
        password: 'pässwörd ä');

    expect(attempt.opened, isTrue);
    expect(await _bytes(attempt.key!), await _bytes(drive.key));
  });

  test(
      'a wallet that cancels is walletDeclined; one that fails otherwise is '
      'walletFailed; neither is asked again in the background', () async {
    final wander = FakeWander(wallet);
    final drive = await makeWebPrivateDrive(
        wallet: wallet, driveId: _driveA, password: 'pw');
    final other = await makeWebPrivateDrive(
        wallet: wallet, driveId: _driveB, password: 'pw');

    wander.cancel = true;
    final cancelled = await unlocker.tryPassword(
        wallet: wander.wallet,
        driveTx: drive.tx,
        data: drive.data,
        password: 'pw');
    wander
      ..cancel = false
      ..fail = true;
    final failed = await unlocker.tryPassword(
        wallet: wander.wallet,
        driveTx: other.tx,
        data: other.data,
        password: 'pw');

    expect(cancelled.failure, DriveUnlockFailure.walletDeclined);
    expect(failed.failure, DriveUnlockFailure.walletFailed);
    expect(session.walletDeclined(owner, _driveB), isTrue);
  });

  test(
      'Cancel on the Wander prompt is walletDeclined, and the rest of the '
      'pass asks Wander nothing', () async {
    final wander = FakeWander(wallet);
    final drive = await makeWebPrivateDrive(
        wallet: wallet, driveId: _driveA, password: 'pw');
    final other = await makeWebPrivateDrive(
        wallet: wallet, driveId: _driveB, password: 'pw');
    final budget = WalletPromptBudget(WalletPromptBudget.perPass);

    wander.gaveUp = true;
    final first = await unlocker.tryPassword(
        wallet: wander.wallet,
        driveTx: drive.tx,
        data: drive.data,
        password: 'pw',
        promptBudget: budget);
    wander.gaveUp = false;
    final next = await unlocker.tryPassword(
        wallet: wander.wallet,
        driveTx: other.tx,
        data: other.data,
        password: 'pw',
        promptBudget: budget);

    expect(first.failure, DriveUnlockFailure.walletDeclined);
    expect(next.failure, DriveUnlockFailure.walletDeclined);
    expect(wander.prompts, 1, reason: 'one Cancel for every drive in the pass');
  });

  test(
      'Wander reconnected on another wallet ends the pass: nothing more is '
      'signed with it, and nothing is kept', () async {
    final wander = FakeWander(wallet);
    final drive = await makeWebPrivateDrive(
        wallet: wallet, driveId: _driveA, password: 'pw');
    final other = await makeWebPrivateDrive(
        wallet: wallet, driveId: _driveB, password: 'pw');
    final budget = WalletPromptBudget(WalletPromptBudget.perPass);

    wander.otherWallet = true;
    final first = await unlocker.tryPassword(
        wallet: wander.wallet,
        driveTx: drive.tx,
        data: drive.data,
        password: 'pw',
        promptBudget: budget);
    wander.otherWallet = false;
    final next = await unlocker.tryPassword(
        wallet: wander.wallet,
        driveTx: other.tx,
        data: other.data,
        password: 'pw',
        promptBudget: budget);

    expect(first.failure, DriveUnlockFailure.walletDeclined);
    expect(next.failure, DriveUnlockFailure.walletDeclined);
    expect(wander.prompts, 1);
    expect(session.holdsSignatureFor(owner, _driveA), isFalse);
  });

  test(
      'after Cancel on "Wander needs your permission again", a pass over '
      'several drives is quiet, and one drive the person asked for is not',
      () async {
    ArConnectPrompt.reset();
    addTearDown(ArConnectPrompt.reset);
    final shown = <ArConnectUnavailableReason>[];
    ArConnectPrompt.registerRetryPrompt((reason, _) async {
      shown.add(reason);
      return false;
    });
    final wander = FakeWander(wallet)..missingPermission = true;
    final saved = await wander.savedWallet();
    final drive = await makeWebPrivateDrive(
        wallet: wallet, driveId: _driveA, password: 'pw');
    final other = await makeWebPrivateDrive(
        wallet: wallet, driveId: _driveB, password: 'pw');

    // The person cancels the prompt once (a write, say).
    await expectLater(
      ArConnectPrompt.ask<String>(
          wander,
          () async => throw Exception(
              'Missing permission(s) for "signature": SIGNATURE')),
      throwsA(isA<ArConnectUnavailableException>()),
    );
    expect(shown, hasLength(1));

    // Discovery: quiet.
    final pass = await unlocker.tryPassword(
        wallet: saved,
        driveTx: drive.tx,
        data: drive.data,
        password: 'pw',
        promptBudget: WalletPromptBudget(WalletPromptBudget.perPass));
    expect(pass.failure, DriveUnlockFailure.walletDeclined);
    expect(shown, hasLength(1));

    // One drive, asked for: offered Reconnect.
    final asked = await unlocker.tryPassword(
        wallet: saved, driveTx: other.tx, data: other.data, password: 'pw');
    expect(asked.failure, DriveUnlockFailure.walletDeclined);
    expect(shown, hasLength(2));
  });

  test('isWalletCancellation: Wander\'s cancels, and nothing else', () {
    for (final cancel in [
      'User cancelled the AuthRequest',
      'User rejected the signature request',
      'User rejected the request',
      'Request canceled by the user',
    ]) {
      expect(isWalletCancellation(Exception(cancel)), isTrue, reason: cancel);
    }
    for (final failure in [
      'Wallet is locked',
      'The message port closed before a response was received.',
      'The operation was aborted.',
      'Permission denied',
    ]) {
      expect(isWalletCancellation(Exception(failure)), isFalse,
          reason: failure);
    }
  });

  group('resolveForDiscovery', () {
    test('a key in memory that opens the drive is used without signing',
        () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'other');
      await db.driveDao
          .putDriveKeyInMemory(driveID: _driveA, driveKey: drive.key);
      signer.signatures = 0;

      final attempt = await unlocker.resolveForDiscovery(
          wallet: wallet, driveTx: drive.tx, data: drive.data, password: 'pw');

      expect(attempt.opened, isTrue);
      expect(signer.signatures, 0);
    });

    test('a key stored on the device is used, and put in memory', () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'other');
      signer.signatures = 0;

      final attempt = await unlocker.resolveForDiscovery(
        wallet: wallet,
        driveTx: drive.tx,
        data: drive.data,
        password: 'pw',
        storedKey: (_) async => drive.key,
      );

      expect(attempt.opened, isTrue);
      expect(signer.signatures, 0);
      expect(await _bytes((await db.driveDao.getDriveKeyFromMemory(_driveA))!),
          await _bytes(drive.key));
    });

    test('a wrong stored key is not kept, and the password is still tried',
        () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'pw');

      final attempt = await unlocker.resolveForDiscovery(
        wallet: wallet,
        driveTx: drive.tx,
        data: drive.data,
        password: 'pw',
        storedKey: (_) async => DriveKey(SecretKey(List.filled(32, 2)), true),
      );

      expect(attempt.opened, isTrue);
      expect(await _bytes(attempt.key!), await _bytes(drive.key));
      expect(await _bytes((await db.driveDao.getDriveKeyFromMemory(_driveA))!),
          await _bytes(drive.key));
    });

    test('a wrong stored key is not kept even when the password fails too',
        () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'other');

      final attempt = await unlocker.resolveForDiscovery(
        wallet: wallet,
        driveTx: drive.tx,
        data: drive.data,
        password: 'pw',
        storedKey: (_) async => DriveKey(SecretKey(List.filled(32, 2)), true),
      );

      expect(attempt.opened, isFalse);
      expect(await db.driveDao.getDriveKeyFromMemory(_driveA), isNull);
    });

    test(
        'a key that does not open the drive is never kept: a wrong key in '
        'memory would be found first on every later pass', () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'other');

      final attempt = await unlocker.resolveForDiscovery(
          wallet: wallet, driveTx: drive.tx, data: drive.data, password: 'pw');

      expect(attempt.failure, DriveUnlockFailure.wrongPassword);
      expect(await db.driveDao.getDriveKeyFromMemory(_driveA), isNull);
    });

    test('the sign-in password opens it, and the key goes into memory',
        () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'pw');

      final attempt = await unlocker.resolveForDiscovery(
          wallet: wallet, driveTx: drive.tx, data: drive.data, password: 'pw');

      expect(attempt.opened, isTrue);
      expect(await _bytes((await db.driveDao.getDriveKeyFromMemory(_driveA))!),
          await _bytes(drive.key));
    });

    test(
        'a drive this device was told not to remember opens from memory '
        'only: neither the sign-in password nor the wallet is tried', () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'pw');
      signer.signatures = 0;

      final attempt = await unlocker.resolveForDiscovery(
        wallet: wallet,
        driveTx: drive.tx,
        data: drive.data,
        password: 'pw',
        forgotten: true,
      );

      expect(attempt.failure, DriveUnlockFailure.notTried);
      expect(PrivateDriveVerdict.of(attempt), PrivateDriveVerdict.locked);
      expect(signer.signatures, 0);

      // Opened this session with Remember off: its key in memory still works.
      await db.driveDao
          .putDriveKeyInMemory(driveID: _driveA, driveKey: drive.key);
      final again = await unlocker.resolveForDiscovery(
        wallet: wallet,
        driveTx: drive.tx,
        data: drive.data,
        password: 'pw',
        forgotten: true,
      );
      expect(again.opened, isTrue);
    });

    test('a drive whose prompt was cancelled is not asked again', () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'pw');
      session.markWalletDeclined(owner, _driveA);
      signer.signatures = 0;

      final attempt = await unlocker.resolveForDiscovery(
        wallet: wallet,
        driveTx: drive.tx,
        data: drive.data,
        password: 'pw',
        mayAskWallet: false,
      );

      expect(attempt.failure, DriveUnlockFailure.walletDeclined);
      expect(signer.signatures, 0);
    });
  });

  group('unlock', () {
    late PrivateDriveFixture a;
    late PrivateDriveFixture b;
    late PrivateDriveFixture c;

    setUp(() async {
      a = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'shared', name: 'A');
      b = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveB, password: 'shared', name: 'B');
      c = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveC, password: 'different', name: 'C');
      onChain([a, b, c]);
      session.setLockedDrives(
          owner, [locked(_driveA), locked(_driveB), locked(_driveC)]);
    });

    test(
        'opens the drive and every other locked drive the password opens, '
        'and keeps each key as an unlocked drive\'s is kept', () async {
      final result = await unlocker.unlock(
        wallet: wallet,
        profileKey: profileKey,
        driveId: _driveA,
        password: 'shared',
      );

      expect(result.openedDriveIds, [_driveA, _driveB]);
      expect(session.currentLockedDrives.map((d) => d.driveId), [_driveC]);

      for (final drive in [a, b]) {
        final row =
            await db.driveDao.driveById(driveId: drive.driveId).getSingle();
        expect(row.name, drive.driveId == _driveA ? 'A' : 'B');
        expect(
          await _bytes(
              (await db.driveDao.getDriveKey(drive.driveId, profileKey))!),
          await _bytes(drive.key),
        );
        expect(
          await _bytes(
              (await db.driveDao.getDriveKeyFromMemory(drive.driveId))!),
          await _bytes(drive.key),
        );
      }

      expect(await db.driveDao.driveById(driveId: _driveC).getSingleOrNull(),
          isNull);
    });

    test('without try-on-others only the one drive opens', () async {
      final result = await unlocker.unlock(
        wallet: wallet,
        profileKey: profileKey,
        driveId: _driveA,
        password: 'shared',
        tryOthers: false,
      );

      expect(result.openedDriveIds, [_driveA]);
      expect(session.isLocked(_driveB), isTrue);
    });

    test('a wrong password writes nothing and keeps nothing', () async {
      final result = await unlocker.unlock(
        wallet: wallet,
        profileKey: profileKey,
        driveId: _driveA,
        password: 'wrong',
      );

      expect(result.failure, DriveUnlockFailure.wrongPassword);
      expect(await db.driveDao.allDrives().get(), isEmpty);
      expect(await db.driveDao.getDriveKeyFromMemory(_driveA), isNull);
      expect(session.isLocked(_driveA), isTrue);
    });

    test('an unreadable drive is unavailable, never a wrong password',
        () async {
      when(() => arweave.getLatestDriveTx(_driveA, owner,
              maxRetries: any(named: 'maxRetries')))
          .thenThrow(Exception('offline'));

      final result = await unlocker.unlock(
        wallet: wallet,
        profileKey: profileKey,
        driveId: _driveA,
        password: 'shared',
      );

      expect(result.failure, DriveUnlockFailure.unavailable);
      expect(await db.driveDao.allDrives().get(), isEmpty);
    });

    test(
        'asking for a drive brings its wallet prompt back; the others whose '
        'prompt was cancelled are not asked', () async {
      // A fresh session: no signature held for any drive.
      session.markWalletDeclined(owner, _driveA);
      session.markWalletDeclined(owner, _driveB);
      signer.signatures = 0;

      final result = await unlocker.unlock(
        wallet: wallet,
        profileKey: profileKey,
        driveId: _driveA,
        password: 'shared',
      );

      expect(result.openedDriveIds, [_driveA]);
      // A signed, B skipped, C (never declined) signed.
      expect(signer.signatures, 2);
      expect(session.isLocked(_driveB), isTrue);
    });

    test('Remember on this device off: the drives open, and nothing is stored',
        () async {
      final result = await unlocker.unlock(
        wallet: wallet,
        profileKey: profileKey,
        driveId: _driveA,
        password: 'shared',
        remember: false,
      );

      expect(result.openedDriveIds, [_driveA, _driveB]);
      for (final id in [_driveA, _driveB]) {
        final row = await db.driveDao.driveById(driveId: id).getSingle();
        expect(row.encryptedKey, isNull, reason: 'no key stored for $id');
        // Readable this session, from memory.
        expect(await db.driveDao.getDriveKey(id, profileKey), isNotNull);
      }
      expect(await db.driveDao.forgottenDriveIds(), {_driveA, _driveB});

      // A reload: nothing to open them with.
      await db.driveDao.clearSessionMemory();
      expect(await db.driveDao.getDriveKey(_driveA, profileKey), isNull);
    });

    test('Remember on: stored, and an earlier "don\'t remember" is cleared',
        () async {
      await db.driveDao
          .keepDriveKeyForSession(driveId: _driveA, driveKey: a.key);
      await db.driveDao.clearSessionMemory();

      await unlocker.unlock(
        wallet: wallet,
        profileKey: profileKey,
        driveId: _driveA,
        password: 'shared',
        tryOthers: false,
      );

      expect(await db.driveDao.forgottenDriveIds(), isEmpty);
      expect(
          await db.driveDao.getStoredDriveKey(_driveA, profileKey), isNotNull);
    });
  });

  group('verifyDrivePassword', () {
    LockedDrive lockedAt(String driveId, int year) => LockedDrive(
          driveId: driveId,
          ownerAddress: owner,
          signatureType: DriveSignatureType.v2,
          lastUpdated: DateTime(year),
        );

    setUp(() {
      when(() => arweave.cachedUserDriveCreationTimes(any())).thenReturn({});
    });

    test(
        'the password is proven by opening the oldest locked drive by '
        'creation, which stays unlocked with its key kept; nothing else is '
        'tried', () async {
      final newer = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'drive pw', name: 'A');
      final oldest = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveB, password: 'drive pw', name: 'B');
      onChain([newer, oldest]);
      // B was made first, though updated last: creation decides, as at
      // sign-in.
      when(() => arweave.cachedUserDriveCreationTimes(owner))
          .thenReturn({_driveA: DateTime(2023), _driveB: DateTime(2020)});
      session.setLockedDrives(
          owner, [lockedAt(_driveA, 2024), lockedAt(_driveB, 2026)]);
      signer.signatures = 0;

      final failure = await unlocker.verifyDrivePassword(
          wallet: wallet, profileKey: profileKey, password: 'drive pw');

      expect(failure, isNull);
      expect(signer.signatures, 1);
      expect(session.isLocked(_driveB), isFalse);
      expect(session.isLocked(_driveA), isTrue);
      expect(
        await _bytes((await db.driveDao.getDriveKey(_driveB, profileKey))!),
        await _bytes(oldest.key),
      );
      expect(
        await _bytes((await db.driveDao.getDriveKeyFromMemory(_driveB))!),
        await _bytes(oldest.key),
      );
      expect(await db.driveDao.driveById(driveId: _driveA).getSingleOrNull(),
          isNull);
    });

    test('a drive forgotten on this device is not tried, and stays forgotten',
        () async {
      final forgotten = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'drive pw', name: 'A');
      final other = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveB, password: 'drive pw', name: 'B');
      onChain([forgotten, other]);
      await db.driveDao.forgetStoredDriveKeyUnread(_driveA);
      session.setLockedDrives(
          owner, [lockedAt(_driveA, 2020), lockedAt(_driveB, 2026)]);

      final failure = await unlocker.verifyDrivePassword(
          wallet: wallet, profileKey: profileKey, password: 'drive pw');

      expect(failure, isNull, reason: 'proven on the drive not forgotten');
      expect(session.isLocked(_driveA), isTrue);
      expect(session.isLocked(_driveB), isFalse);
      expect(await db.driveDao.forgottenDriveIds(), {_driveA});
      expect(await db.driveDao.getDriveKeyFromMemory(_driveA), isNull);
    });

    test(
        'every locked drive forgotten and none open: the password is checked '
        'on a forgotten one, which stays forgotten with no key kept', () async {
      final forgotten = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'drive pw', name: 'A');
      onChain([forgotten]);
      await db.driveDao.forgetStoredDriveKeyUnread(_driveA);
      session.setLockedDrives(owner, [lockedAt(_driveA, 2020)]);

      expect(
          await unlocker.verifyDrivePassword(
              wallet: wallet, profileKey: profileKey, password: 'drive pw'),
          isNull);
      expect(
          await unlocker.verifyDrivePassword(
              wallet: wallet, profileKey: profileKey, password: 'typo'),
          DriveUnlockFailure.wrongPassword);

      expect(session.isLocked(_driveA), isTrue);
      expect(await db.driveDao.forgottenDriveIds(), {_driveA});
      expect(await db.driveDao.getDriveKeyFromMemory(_driveA), isNull);
      expect(await db.driveDao.allDrives().get(), isEmpty);
    });

    test(
        'a password that derives a key but opens none is wrongPassword, and '
        'no key is kept', () async {
      final a = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'drive pw');
      final b = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveB, password: 'drive pw');
      onChain([a, b]);
      session.setLockedDrives(
          owner, [lockedAt(_driveA, 2024), lockedAt(_driveB, 2025)]);

      final failure = await unlocker.verifyDrivePassword(
          wallet: wallet, profileKey: profileKey, password: 'typo');

      expect(failure, DriveUnlockFailure.wrongPassword);
      expect(await db.driveDao.allDrives().get(), isEmpty);
      expect(await db.driveDao.getDriveKeyFromMemory(_driveA), isNull);
      expect(await db.driveDao.getDriveKeyFromMemory(_driveB), isNull);
      expect(session.isLocked(_driveA), isTrue);
    });

    test(
        'a drive core-js made with a non-ASCII password proves it: both '
        'encodings are tried', () async {
      final drive = await makePrivateDrive(
        wallet: wallet,
        driveId: _driveA,
        passwordInfo: coreJsPasswordInfo('pässwörd ä'),
      );
      onChain([drive]);
      session.setLockedDrives(owner, [lockedAt(_driveA, 2024)]);

      expect(
        await unlocker.verifyDrivePassword(
            wallet: wallet, profileKey: profileKey, password: 'pässwörd ä'),
        isNull,
      );
    });

    test('Wander is asked at most three times, however many drives are locked',
        () async {
      final wander = FakeWander(wallet);
      final ids = [_driveA, _driveB, _driveC, _driveD, _driveE];
      final drives = [
        for (final id in ids)
          await makeWebPrivateDrive(
              wallet: wallet, driveId: id, password: 'drive pw'),
      ];
      onChain(drives);
      session.setLockedDrives(owner, [
        for (var i = 0; i < ids.length; i++) lockedAt(ids[i], 2020 + i),
      ]);

      final failure = await unlocker.verifyDrivePassword(
          wallet: wander.wallet, profileKey: profileKey, password: 'typo');

      expect(failure, DriveUnlockFailure.wrongPassword);
      expect(wander.prompts, WalletPromptBudget.perPass);
    });

    test(
        'out of prompts, a drive whose signature is already held is still '
        'tried', () async {
      final wander = FakeWander(wallet);
      final ids = [_driveA, _driveB, _driveC, _driveD, _driveE];
      final drives = [
        for (final id in ids)
          await makeWebPrivateDrive(
              wallet: wallet,
              driveId: id,
              password: id == _driveE ? 'drive pw' : 'other'),
      ];
      onChain(drives);
      session.setLockedDrives(owner, [
        for (var i = 0; i < ids.length; i++) lockedAt(ids[i], 2020 + i),
      ]);
      // An earlier attempt left E's signature in the session.
      await unlocker.tryPassword(
          wallet: wander.wallet,
          driveTx: drives.last.tx,
          data: drives.last.data,
          password: 'nope');
      wander.prompts = 0;

      final failure = await unlocker.verifyDrivePassword(
          wallet: wander.wallet, profileKey: profileKey, password: 'drive pw');

      expect(failure, isNull);
      expect(wander.prompts, WalletPromptBudget.perPass);
      expect(session.isLocked(_driveE), isFalse);
    });

    test('a cancelled Wander prompt stops the check quietly', () async {
      final wander = FakeWander(wallet)..cancel = true;
      final drive = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'drive pw');
      onChain([drive]);
      session.setLockedDrives(owner, [lockedAt(_driveA, 2024)]);

      expect(
        await unlocker.verifyDrivePassword(
            wallet: wander.wallet,
            profileKey: profileKey,
            password: 'drive pw'),
        DriveUnlockFailure.walletDeclined,
      );
    });

    test(
        'with nothing locked, the oldest known private drive is opened to '
        'check it; with nothing at all, there is no verdict', () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveA, password: 'drive pw');
      onChain([drive]);

      expect(
        await unlocker.verifyDrivePassword(
            wallet: wallet,
            profileKey: profileKey,
            password: 'drive pw',
            knownPrivateDriveIds: [_driveA]),
        isNull,
      );
      expect(
        await unlocker.verifyDrivePassword(
            wallet: wallet,
            profileKey: profileKey,
            password: 'typo',
            knownPrivateDriveIds: [_driveA]),
        DriveUnlockFailure.wrongPassword,
      );
      expect(
        await unlocker.verifyDrivePassword(
            wallet: wallet, profileKey: profileKey, password: 'drive pw'),
        DriveUnlockFailure.unavailable,
      );
    });
  });
}
