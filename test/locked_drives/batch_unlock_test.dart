import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/locked_drives/domain/drive_password_order.dart';
import 'package:ardrive/locked_drives/domain/drive_unlock_session.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/locked_drives/domain/locked_drive.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/locked_drive_fixtures.dart';
import '../test_utils/utils.dart';

String _id(int i) =>
    '00000000-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}';

/// Unlocking every private drive with one Wander approval
/// (`batchSignDataItem`), and every way it falls back to asking drive by
/// drive.
void main() {
  late Wallet jwk;
  late String owner;
  late FakeWander wander;
  late MockArweaveService arweave;
  late Database db;
  late DriveUnlockSession session;
  late DriveUnlocker unlocker;
  final crypto = ArDriveCrypto();
  final profileKey = SecretKey(List.filled(32, 7));

  void onChain(List<PrivateDriveFixture> drives) {
    when(() => arweave.cachedUserDriveCreationTimes(any())).thenReturn({});
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

  /// [passwords.length] private drives, oldest first, the i-th made with
  /// `passwords[i]`.
  Future<List<PrivateDriveFixture>> drivesWith(List<String> passwords) async {
    final drives = [
      for (var i = 0; i < passwords.length; i++)
        await makeWebPrivateDrive(
          wallet: jwk,
          driveId: _id(i),
          password: passwords[i],
          name: 'Drive $i',
          unixTime: 1700000000 + i,
        ),
    ];
    onChain(drives);
    return drives;
  }

  LockedDrive locked(String driveId) => LockedDrive(
        driveId: driveId,
        ownerAddress: owner,
        signatureType: DriveSignatureType.v2,
        lastUpdated: DateTime(2025),
      );

  List<DriveMetadata> metadataOf(List<PrivateDriveFixture> drives) =>
      [for (final drive in drives) (tx: drive.tx, data: drive.data)];

  Future<Uint8List> singleSignature(String driveId) =>
      crypto.walletSignatureForDrive(jwk, driveId, DriveSignatureType.v2);

  setUpAll(() => registerFallbackValue(getTestWallet()));

  setUp(() async {
    ArConnectPrompt.reset();
    jwk = getTestWallet();
    owner = await jwk.getAddress();
    wander = FakeWander(jwk)..batch = true;
    arweave = MockArweaveService();
    db = getTestDb();
    session = DriveUnlockSession();
    unlocker = DriveUnlocker(
      crypto: crypto,
      arweave: arweave,
      driveDao: db.driveDao,
      session: session,
    );
  });

  tearDown(() async {
    ArConnectPrompt.reset();
    await db.close();
  });

  group('signInOneApproval', () {
    test(
        'one prompt signs for every drive, and the signatures are the ones '
        'Wander gives one at a time', () async {
      final drives = await drivesWith(['pw', 'pw', 'pw', 'pw', 'pw']);

      final outcome = await unlocker.signInOneApproval(
        wallet: wander.wallet,
        driveIds: [for (final d in drives) d.driveId],
      );

      expect(outcome, DriveSignatureBatch.signed);
      expect(wander.prompts, 1);
      expect(wander.batches, 1);
      for (final drive in drives) {
        expect(session.signature(owner, drive.driveId, DriveSignatureType.v2),
            await singleSignature(drive.driveId));
      }
    });

    test('a Wander without batch signing is not asked', () async {
      final drives = await drivesWith(['pw', 'pw']);
      wander.batch = false;

      final outcome = await unlocker.signInOneApproval(
        wallet: wander.wallet,
        driveIds: [for (final d in drives) d.driveId],
      );

      expect(outcome, DriveSignatureBatch.notAsked);
      expect(wander.prompts, 0);
    });

    test('a wallet that signs on the device is never batch-asked', () async {
      final drives = await drivesWith(['pw', 'pw']);

      expect(
        await unlocker.signInOneApproval(
          wallet: jwk,
          driveIds: [for (final d in drives) d.driveId],
        ),
        DriveSignatureBatch.notAsked,
      );
    });

    test('one drive to sign for goes its own way: no batch', () async {
      final drives = await drivesWith(['pw']);

      expect(
        await unlocker.signInOneApproval(
          wallet: wander.wallet,
          driveIds: [drives.single.driveId],
        ),
        DriveSignatureBatch.notAsked,
      );
      expect(wander.prompts, 0);
    });

    test(
        'a cancel is one cancel for every drive: each is declined, nothing is '
        'held, and nothing more is asked', () async {
      final drives = await drivesWith(['pw', 'pw', 'pw']);
      wander.cancelBatch = true;

      final outcome = await unlocker.signInOneApproval(
        wallet: wander.wallet,
        driveIds: [for (final d in drives) d.driveId],
      );

      expect(outcome, DriveSignatureBatch.declined);
      expect(wander.prompts, 1);
      for (final drive in drives) {
        expect(session.walletDeclined(owner, drive.driveId), isTrue);
        expect(session.holdsSignatureFor(owner, drive.driveId), isFalse);
      }
    });

    test(
        'a hardware wallet refuses after the approval: unusable for the rest '
        'of the session', () async {
      final drives = await drivesWith(['pw', 'pw']);
      wander.refuseBatch = true;
      final ids = [for (final d in drives) d.driveId];

      expect(
        await unlocker.signInOneApproval(wallet: wander.wallet, driveIds: ids),
        DriveSignatureBatch.unusable,
      );
      expect(session.batchSigningUnusable(owner), isTrue);
      expect(session.walletDeclined(owner, ids.first), isFalse,
          reason: 'not the user: its drives may still be asked one by one');

      expect(
        await unlocker.signInOneApproval(wallet: wander.wallet, driveIds: ids),
        DriveSignatureBatch.notAsked,
      );
      expect(wander.batches, 1);
    });

    test(
        'every signature is checked: item 0 right and the rest wrong keeps '
        'only item 0, stops batches, and drive 1 still opens with its own '
        'password', () async {
      final drives = await drivesWith(['pw', 'pw', 'pw']);
      wander.partialBatch = true;

      final outcome = await unlocker.signInOneApproval(
        wallet: wander.wallet,
        driveIds: [for (final d in drives) d.driveId],
      );

      expect(outcome, DriveSignatureBatch.unusable);
      expect(wander.prompts, 1, reason: 'no second prompt to check it');
      expect(session.signature(owner, drives[0].driveId, DriveSignatureType.v2),
          await singleSignature(drives[0].driveId));
      expect(session.holdsSignatureFor(owner, drives[1].driveId), isFalse);
      expect(session.holdsSignatureFor(owner, drives[2].driveId), isFalse);
      expect(session.batchSigningUnusable(owner), isTrue);

      // Drive 1 is asked for on its own and opens: never "wrong password".
      final attempt = await unlocker.tryPassword(
        wallet: wander.wallet,
        driveTx: drives[1].tx,
        data: drives[1].data,
        password: 'pw',
      );
      expect(attempt.opened, isTrue);
      expect(wander.prompts, 2);
    });

    test('signatures returned out of order fail their check', () async {
      final drives = await drivesWith(['pw', 'pw', 'pw']);
      wander.reverseBatch = true;

      expect(
        await unlocker.signInOneApproval(
          wallet: wander.wallet,
          driveIds: [for (final d in drives) d.driveId],
        ),
        DriveSignatureBatch.unusable,
      );
      // The middle one is in its own place, and is the right one.
      expect(session.holdsSignatureFor(owner, drives[0].driveId), isFalse);
      expect(session.holdsSignatureFor(owner, drives[1].driveId), isTrue);
      expect(session.holdsSignatureFor(owner, drives[2].driveId), isFalse);
    });

    test('random signatures: nothing is kept, and no second prompt', () async {
      final drives = await drivesWith(['pw', 'pw']);
      wander.varyBatch = true;

      expect(
        await unlocker.signInOneApproval(
          wallet: wander.wallet,
          driveIds: [for (final d in drives) d.driveId],
        ),
        DriveSignatureBatch.unusable,
      );
      expect(wander.prompts, 1);
      expect(session.holdsSignatureFor(owner, drives[0].driveId), isFalse);
      expect(session.holdsSignatureFor(owner, drives[1].driveId), isFalse);
      expect(session.batchSigningUnusable(owner), isTrue);
    });

    test('no prompt left in the budget: not asked (an unproven password)',
        () async {
      final drives = await drivesWith(['pw', 'pw']);

      expect(
        await unlocker.signInOneApproval(
          wallet: wander.wallet,
          driveIds: [for (final d in drives) d.driveId],
          promptBudget: WalletPromptBudget(0),
        ),
        DriveSignatureBatch.notAsked,
      );
      expect(wander.prompts, 0);
    });

    test('a batch costs one prompt from the budget', () async {
      final drives = await drivesWith(['pw', 'pw', 'pw']);
      final budget = WalletPromptBudget(3);

      await unlocker.signInOneApproval(
        wallet: wander.wallet,
        driveIds: [for (final d in drives) d.driveId],
        promptBudget: budget,
      );

      expect(budget.remaining, 2);
    });

    test(
        'a batch Wander never answers ends in the Try again prompt; Cancel '
        'there declines every drive', () async {
      final drives = await drivesWith(['pw', 'pw']);
      wander.hangBatch = true;
      ArConnectPrompt.signTimeout = const Duration(milliseconds: 50);
      final reasons = <ArConnectUnavailableReason>[];
      ArConnectPrompt.registerRetryPrompt((reason, _) async {
        reasons.add(reason);
        return false;
      });
      final saved = ArConnectWallet(wander, publicKey: await jwk.getOwner());

      final outcome = await unlocker.signInOneApproval(
        wallet: saved,
        driveIds: [for (final d in drives) d.driveId],
      );

      expect(reasons, [ArConnectUnavailableReason.noAnswer]);
      expect(outcome, DriveSignatureBatch.declined);
      for (final drive in drives) {
        expect(session.walletDeclined(owner, drive.driveId), isTrue);
      }
    });
  });

  group('unlock, trying the others', () {
    test(
        'one prompt opens the drive and every other locked drive with the '
        'same password; the rest stay locked', () async {
      final drives = await drivesWith(['pw', 'pw', 'other', 'pw', 'pw']);
      session
          .setLockedDrives(owner, [for (final d in drives) locked(d.driveId)]);

      final result = await unlocker.unlock(
        wallet: wander.wallet,
        profileKey: profileKey,
        driveId: drives[1].driveId,
        password: 'pw',
      );

      expect(wander.prompts, 1);
      expect(result.openedDriveIds, [
        drives[1].driveId,
        drives[0].driveId,
        drives[3].driveId,
        drives[4].driveId,
      ]);
      expect(session.currentLockedDrives.map((d) => d.driveId),
          [drives[2].driveId]);
    });

    test(
        'drives whose prompt was cancelled earlier are in the batch: the '
        'user asked for all of them', () async {
      final drives = await drivesWith(['pw', 'pw', 'pw']);
      session
          .setLockedDrives(owner, [for (final d in drives) locked(d.driveId)]);
      for (final drive in drives) {
        session.markWalletDeclined(owner, drive.driveId);
      }

      final result = await unlocker.unlock(
        wallet: wander.wallet,
        profileKey: profileKey,
        driveId: drives[0].driveId,
        password: 'pw',
      );

      expect(wander.prompts, 1);
      expect(result.openedDriveIds, hasLength(3));
    });

    test(
        'a cancelled batch leaves every drive locked, asks nothing more, and '
        'the dialog is back where it was', () async {
      final drives = await drivesWith(['pw', 'pw', 'pw']);
      session
          .setLockedDrives(owner, [for (final d in drives) locked(d.driveId)]);
      wander.cancelBatch = true;

      final result = await unlocker.unlock(
        wallet: wander.wallet,
        profileKey: profileKey,
        driveId: drives[0].driveId,
        password: 'pw',
      );

      expect(result.failure, DriveUnlockFailure.walletDeclined);
      expect(wander.prompts, 1);
      expect(session.currentLockedDrives, hasLength(3));
      expect(await db.driveDao.allDrives().get(), isEmpty);
    });

    test('a Wander without batch signing is asked drive by drive, as before',
        () async {
      final drives = await drivesWith(['pw', 'pw', 'pw']);
      session
          .setLockedDrives(owner, [for (final d in drives) locked(d.driveId)]);
      wander.batch = false;

      final result = await unlocker.unlock(
        wallet: wander.wallet,
        profileKey: profileKey,
        driveId: drives[0].driveId,
        password: 'pw',
      );

      expect(result.openedDriveIds, hasLength(3));
      expect(wander.prompts, 3);
      expect(wander.batches, 0);
    });

    test(
        'a batch whose signatures fail their check falls back to drive by drive',
        () async {
      final drives = await drivesWith(['pw', 'pw', 'pw']);
      session
          .setLockedDrives(owner, [for (final d in drives) locked(d.driveId)]);
      wander.varyBatch = true;

      final result = await unlocker.unlock(
        wallet: wander.wallet,
        profileKey: profileKey,
        driveId: drives[0].driveId,
        password: 'pw',
      );

      expect(result.openedDriveIds, hasLength(3));
      // The batch, then the drive asked for and the other two one at a time.
      expect(wander.prompts, 4);
    });

    test('without trying the others, no batch', () async {
      final drives = await drivesWith(['pw', 'pw']);
      session
          .setLockedDrives(owner, [for (final d in drives) locked(d.driveId)]);

      await unlocker.unlock(
        wallet: wander.wallet,
        profileKey: profileKey,
        driveId: drives[0].driveId,
        password: 'pw',
        tryOthers: false,
      );

      expect(wander.batches, 0);
      expect(wander.prompts, 1);
    });
  });

  group('forgotten on this device', () {
    test('discovery never signs for a forgotten drive', () async {
      final drives = await drivesWith(['pw', 'pw', 'pw']);
      await db.driveDao.forgetStoredDriveKeyUnread(drives[0].driveId);

      final outcome = await unlocker.signForDiscovery(
          wallet: wander.wallet, drives: metadataOf(drives));

      expect(outcome, DriveSignatureBatch.signed);
      expect(wander.lastBatchSize, 2);
      expect(session.holdsSignatureFor(owner, drives[0].driveId), isFalse);
    });

    test(
        'trying the others leaves a forgotten drive out of the batch and '
        'locked, and does not remember it again', () async {
      final drives = await drivesWith(['pw', 'pw', 'pw']);
      session
          .setLockedDrives(owner, [for (final d in drives) locked(d.driveId)]);
      await db.driveDao.forgetStoredDriveKeyUnread(drives[2].driveId);

      final result = await unlocker.unlock(
        wallet: wander.wallet,
        profileKey: profileKey,
        driveId: drives[0].driveId,
        password: 'pw',
      );

      expect(result.openedDriveIds, [drives[0].driveId, drives[1].driveId]);
      expect(wander.lastBatchSize, 2);
      expect(session.holdsSignatureFor(owner, drives[2].driveId), isFalse);
      expect(session.isLocked(drives[2].driveId), isTrue);
      expect(await db.driveDao.forgottenDriveIds(), {drives[2].driveId});
    });

    test('unlocked directly, a forgotten drive opens and is remembered again',
        () async {
      final drives = await drivesWith(['pw', 'pw']);
      session
          .setLockedDrives(owner, [for (final d in drives) locked(d.driveId)]);
      await db.driveDao.forgetStoredDriveKeyUnread(drives[0].driveId);

      final result = await unlocker.unlock(
        wallet: wander.wallet,
        profileKey: profileKey,
        driveId: drives[0].driveId,
        password: 'pw',
        tryOthers: false,
      );

      expect(result.openedDriveIds, [drives[0].driveId]);
      expect(await db.driveDao.forgottenDriveIds(), isEmpty);
    });
  });

  group('signForDiscovery', () {
    test(
        'only drives that would ask the wallet are signed: not ones with a '
        'key, a stored key, a held signature or a cancelled prompt', () async {
      final drives = await drivesWith(['pw', 'pw', 'pw', 'pw', 'pw', 'pw']);
      await db.driveDao.putDriveKeyInMemory(
          driveID: drives[0].driveId, driveKey: drives[0].key);
      session.rememberSignature(owner, drives[2].driveId, DriveSignatureType.v2,
          await singleSignature(drives[2].driveId));
      session.markWalletDeclined(owner, drives[3].driveId);

      final outcome = await unlocker.signForDiscovery(
        wallet: wander.wallet,
        drives: metadataOf(drives),
        storedKey: (driveId) async =>
            driveId == drives[1].driveId ? drives[1].key : null,
      );

      expect(outcome, DriveSignatureBatch.signed);
      expect(wander.prompts, 1);
      // Drives 4 and 5 only.
      expect(wander.lastBatchSize, 2);
      expect(session.holdsSignatureFor(owner, drives[4].driveId), isTrue);
      expect(session.holdsSignatureFor(owner, drives[5].driveId), isTrue);
      expect(session.holdsSignatureFor(owner, drives[1].driveId), isFalse);
      expect(session.holdsSignatureFor(owner, drives[3].driveId), isFalse);
    });

    test('then resolving each drive asks nothing', () async {
      final drives = await drivesWith(['pw', 'pw', 'other']);

      await unlocker.signForDiscovery(
          wallet: wander.wallet, drives: metadataOf(drives));
      final attempts = [
        for (final drive in drives)
          await unlocker.resolveForDiscovery(
            wallet: wander.wallet,
            driveTx: drive.tx,
            data: drive.data,
            password: 'pw',
            mayAskWallet: false,
            promptBudget: WalletPromptBudget(3),
          ),
      ];

      expect(wander.prompts, 1);
      expect([for (final a in attempts) a.opened], [true, true, false]);
      expect(attempts[2].failure, DriveUnlockFailure.wrongPassword);
    });

    test('a drive forgotten on this device is not signed for', () async {
      final drives = await drivesWith(['pw', 'pw', 'pw']);
      await db.driveDao.forgetStoredDriveKeyUnread(drives[0].driveId);

      await unlocker.signForDiscovery(
          wallet: wander.wallet, drives: metadataOf(drives));

      expect(wander.lastBatchSize, 2);
      expect(session.holdsSignatureFor(owner, drives[0].driveId), isFalse);
    });

    test(
        'no password at all (a browser wallet sign-in) asks the wallet nothing, '
        'and opens nothing', () async {
      final drives = await drivesWith(['pw']);

      final attempt = await unlocker.tryPassword(
        wallet: wander.wallet,
        driveTx: drives[0].tx,
        data: drives[0].data,
        password: '',
      );

      expect(attempt.opened, isFalse);
      expect(wander.prompts, 0);
    });

    test('an unproven password has no prompts to spend: nothing is asked',
        () async {
      final drives = await drivesWith(['pw', 'pw']);

      expect(
        await unlocker.signForDiscovery(
          wallet: wander.wallet,
          drives: metadataOf(drives),
          promptBudget: WalletPromptBudget(0),
        ),
        DriveSignatureBatch.notAsked,
      );
      expect(wander.prompts, 0);
    });
  });

  test(
      'after Cancel on "Wander needs your permission again", a discovery '
      'batch is quiet, and an Unlock\'s own drive still prompts', () async {
    final shown = <ArConnectUnavailableReason>[];
    ArConnectPrompt.registerRetryPrompt((reason, _) async {
      shown.add(reason);
      return false;
    });
    final drives = await drivesWith(['pw', 'pw', 'pw']);
    wander.missingPermission = true;
    final saved = await wander.savedWallet();

    // The person cancels the prompt once (a write, say).
    await expectLater(
      ArConnectPrompt.ask<String>(
          wander,
          () async => throw Exception(
              'Missing permission(s) for "signature": SIGNATURE')),
      throwsA(isA<ArConnectUnavailableException>()),
    );
    expect(shown, hasLength(1));

    // Discovery's batch: quiet, and its drives are left for Unlock.
    expect(
      await unlocker.signForDiscovery(
        wallet: saved,
        drives: metadataOf(drives),
        promptBudget: WalletPromptBudget(WalletPromptBudget.perPass),
      ),
      DriveSignatureBatch.declined,
    );
    expect(shown, hasLength(1));

    // Unlock, with the others: the drive asked for is in this batch, so the
    // person is offered Reconnect again.
    session.setLockedDrives(owner, [for (final d in drives) locked(d.driveId)]);
    final result = await unlocker.unlock(
      wallet: saved,
      profileKey: profileKey,
      driveId: drives[0].driveId,
      password: 'pw',
    );
    expect(shown, hasLength(2));
    expect(shown.last, ArConnectUnavailableReason.noPermission);
    expect(result.failure, DriveUnlockFailure.walletDeclined);
  });

  group('v1 drives in a batch', () {
    /// A v1 drive with a stored signature record (no `Signature-Type` tag,
    /// as the migration leaves it), a v2 drive, a v1 drive without a record,
    /// and the same without its `Signature-Type` tag. All open with 'pw'.
    Future<List<PrivateDriveFixture>> mixed() async {
      final withRecord = await makeWebPrivateDrive(
          wallet: jwk,
          driveId: _id(0),
          password: 'pw',
          signatureType: DriveSignatureType.v1,
          withRecord: true,
          unixTime: 1700000000);
      final v2 = await makeWebPrivateDrive(
          wallet: jwk, driveId: _id(1), password: 'pw', unixTime: 1700000001);
      final noRecord = await makeWebPrivateDrive(
          wallet: jwk,
          driveId: _id(2),
          password: 'pw',
          signatureType: DriveSignatureType.v1,
          unixTime: 1700000002);
      final untagged = await makeWebPrivateDrive(
          wallet: jwk,
          driveId: _id(3),
          password: 'pw',
          signatureType: DriveSignatureType.v1,
          unixTime: 1700000003);
      final untaggedTx = FakeDriveTx(
        id: untagged.tx.id,
        ownerAddress: owner,
        tags: {
          for (final tag in untagged.tx.tags)
            if (tag.name != 'Signature-Type') tag.name: tag.value,
        },
      );
      final drives = [
        withRecord,
        v2,
        noRecord,
        PrivateDriveFixture(
          driveId: untagged.driveId,
          tx: untaggedTx,
          data: untagged.data,
          key: untagged.key,
        ),
      ];
      onChain(drives);
      return drives;
    }

    test(
        'discovery: v1 with a record and v2 are in the batch; v1 without one '
        '(tagged or not) is left out and signs on its own', () async {
      final drives = await mixed();
      // The v2 signature the migration's record is encrypted under, and the
      // v1 signatures, are separate prompts.
      final budget = WalletPromptBudget(WalletPromptBudget.perPass);

      expect(
        await unlocker.signForDiscovery(
            wallet: wander.wallet,
            drives: metadataOf(drives),
            promptBudget: budget),
        DriveSignatureBatch.signed,
      );
      expect(wander.lastBatchSize, 2);
      expect(session.holdsSignatureFor(owner, _id(0)), isTrue);
      expect(session.holdsSignatureFor(owner, _id(1)), isTrue);
      expect(session.holdsSignatureFor(owner, _id(2)), isFalse);
      expect(session.holdsSignatureFor(owner, _id(3)), isFalse);

      final opened = [
        for (final drive in drives)
          (await unlocker.resolveForDiscovery(
            wallet: wander.wallet,
            driveTx: drive.tx,
            data: drive.data,
            password: 'pw',
            mayAskWallet: false,
            promptBudget: budget,
          ))
              .opened,
      ];
      expect(opened, [true, true, true, true]);
      // The batch, then one v1 signature for each drive without a record.
      expect(wander.prompts, 3);
    });

    test('discovery: only v1 drives without a record means no batch', () async {
      final drives = (await mixed()).sublist(2);

      expect(
        await unlocker.signForDiscovery(
            wallet: wander.wallet, drives: metadataOf(drives)),
        DriveSignatureBatch.notAsked,
      );
      expect(wander.batches, 0);
      expect(wander.prompts, 0);
    });

    test(
        'unlock with the others: the batch leaves out the v1 drive without a '
        'record, which is asked for on its own', () async {
      final drives = (await mixed()).sublist(0, 3);
      final types = [
        DriveSignatureType.v1,
        DriveSignatureType.v2,
        DriveSignatureType.v1,
      ];
      session.setLockedDrives(owner, [
        for (var i = 0; i < drives.length; i++)
          LockedDrive(
            driveId: drives[i].driveId,
            ownerAddress: owner,
            signatureType: types[i],
            lastUpdated: DateTime(2025),
          ),
      ]);

      final result = await unlocker.unlock(
        wallet: wander.wallet,
        profileKey: profileKey,
        driveId: _id(1),
        password: 'pw',
      );

      expect(wander.lastBatchSize, 2);
      expect(result.openedDriveIds, hasLength(3));
      expect(wander.prompts, 2, reason: 'the batch, then the v1 signature');
    });
  });

  group('checking a drive signature', () {
    test(
        'the deterministic signature passes; another drive\'s or random '
        'bytes fail', () async {
      final publicKey = await jwk.getOwner();
      final right = await singleSignature(_id(1));

      expect(
          await crypto.isDriveSignature(
              owner: publicKey, driveId: _id(1), signature: right),
          isTrue);
      expect(
          await crypto.isDriveSignature(
              owner: publicKey,
              driveId: _id(1),
              signature: await singleSignature(_id(2))),
          isFalse);
      expect(
          await crypto.isDriveSignature(
              owner: publicKey,
              driveId: _id(1),
              signature: Uint8List.fromList(List.filled(512, 7))),
          isFalse);
    });

    test(
        'a single Wander signature is checked too: one no key can come from '
        'is refused, and no key is made', () async {
      wander.varyV2 = true;

      await expectLater(
        crypto.walletSignatureForDrive(
            wander.wallet, _id(1), DriveSignatureType.v2),
        throwsA(isA<WalletCantMakeDriveKeysException>()),
      );
      await expectLater(
        crypto.deriveDriveKey(
            wander.wallet, _id(1), 'pw', DriveSignatureType.v2, null),
        throwsA(isA<WalletCantMakeDriveKeysException>()),
      );

      wander.varyV2 = false;
      expect(
          await crypto.walletSignatureForDrive(
              wander.wallet, _id(1), DriveSignatureType.v2),
          await singleSignature(_id(1)));
    });

    test(
        'unlocking with a wallet like that is a wallet failure, never '
        '"wrong password"', () async {
      final drives = await drivesWith(['pw']);
      wander.varyV2 = true;

      final attempt = await unlocker.tryPassword(
        wallet: wander.wallet,
        driveTx: drives.single.tx,
        data: drives.single.data,
        password: 'pw',
      );

      expect(attempt.failure, DriveUnlockFailure.walletFailed);
      expect(session.holdsSignatureFor(owner, drives.single.driveId), isFalse);
    });
  });

  group('which drives a password is tried on first', () {
    test('made before 3.0 by web or the CLI, then by desktop, then since', () {
      final before = drivePasswordEraCutoff.subtract(const Duration(days: 1));
      final after = drivePasswordEraCutoff.add(const Duration(days: 1));

      expect(
          drivePasswordTryRank(createdAt: before, appName: 'ArDrive-App'), 0);
      expect(
          drivePasswordTryRank(createdAt: before, appName: 'ArDrive-CLI'), 0);
      expect(drivePasswordTryRank(createdAt: before), 0);
      for (final desktop in [
        'ArDrive-Desktop',
        'ArDrive-Sync',
        'ArDrive-Core'
      ]) {
        expect(drivePasswordTryRank(createdAt: before, appName: desktop), 1,
            reason: desktop);
      }
      expect(drivePasswordTryRank(createdAt: after, appName: 'ArDrive-App'), 2);
    });

    test('within a rank, oldest first', () {
      FakeDriveTx tx(String id, String app) =>
          FakeDriveTx(id: id, ownerAddress: 'o', tags: {'App-Name': app});
      final created = {
        'old desktop': DateTime.utc(2022),
        'new web': DateTime.utc(2024),
        'old web': DateTime.utc(2021),
        'after 3.0': drivePasswordEraCutoff.add(const Duration(days: 30)),
      };
      final txs = [
        tx('after 3.0', 'ArDrive-App'),
        tx('new web', 'ArDrive-App'),
        tx('old desktop', 'ArDrive-Desktop'),
        tx('old web', 'ArDrive-App'),
      ]..sort((a, b) => compareForPasswordTries(a, b, (t) => created[t.id]!));

      expect([for (final t in txs) t.id],
          ['old web', 'new web', 'old desktop', 'after 3.0']);
    });
  });
}
