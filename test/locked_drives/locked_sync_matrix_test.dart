// Drive discovery and the sync that follows an unlock, with 0, 1, 2 and 5
// of 5 private drives open, for a keyfile wallet and for Wander, and while
// drives are unlocked or forgotten mid-pass. Real drive keys and a real
// database; the gateway alone is mocked, as in
// locked_drive_isolation_test.dart.
import 'dart:async';
import 'dart:convert';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/locked_drives/domain/drive_unlock_session.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/locked_drives/domain/locked_drive.dart';
import 'package:ardrive/locked_drives/domain/user_drive_discovery.dart';
import 'package:ardrive/locked_drives/presentation/unlock_drive_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/sync/data/snapshot_validation_service.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/utils/batch_processor.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/locked_drive_fixtures.dart';
import '../test_utils/utils.dart';

class _MockDataGatewayFallback extends Mock implements DataGatewayFallback {}

class _MockBatchProcessor extends Mock implements BatchProcessor {}

class _MockSnapshotValidationService extends Mock
    implements SnapshotValidationService {}

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

typedef _Resolver = Future<DriveKeyAttempt> Function(
    TransactionCommonMixin driveTx, Uint8List data);

String _id(int i) => '00000000-0000-4000-8000-00000000000$i';

void main() {
  late SignatureCounter signer;
  late Wallet wallet;
  late String owner;
  late MockArweaveService arweave;
  late Database db;
  late DriveUnlockSession session;
  late DriveUnlocker unlocker;
  late SyncRepository syncRepository;
  late List<PrivateDriveFixture> onChain;
  Completer<void>? holdDiscovery;
  late Completer<void> reachedHold;
  final profileKey = SecretKey(List.filled(32, 9));

  setUpAll(() {
    registerFallbackValue(getTestWallet());
    registerFallbackValue((TransactionCommonMixin tx, Uint8List data) async =>
        const DriveKeyAttempt.failed(DriveUnlockFailure.unavailable));
  });

  Future<void> chain(List<String> passwords) async {
    onChain = [
      for (var i = 0; i < passwords.length; i++)
        await makeWebPrivateDrive(
          wallet: wallet,
          driveId: _id(i),
          password: passwords[i],
          name: 'Drive $i',
          unixTime: 1700000000 + i,
        ),
    ];
    for (final drive in onChain) {
      when(() => arweave.getLatestDriveTx(drive.driveId, owner,
              maxRetries: any(named: 'maxRetries')))
          .thenAnswer((_) async => drive.tx);
      when(() => arweave.getEntityDataBytes(drive.tx.id,
              configuredGatewayOnly: any(named: 'configuredGatewayOnly')))
          .thenAnswer((_) async => drive.data);
    }
  }

  setUp(() async {
    holdDiscovery = null;
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
    onChain = [];

    when(() => arweave.getUniqueUserDriveEntities(
          any(),
          any(),
          onDriveRead: any(named: 'onDriveRead'),
          onDriveUnlocked: any(named: 'onDriveUnlocked'),
          resolvePrivateDriveKey: any(named: 'resolvePrivateDriveKey'),
          beforeResolvingPrivateDrives:
              any(named: 'beforeResolvingPrivateDrives'),
        )).thenAnswer((invocation) async {
      final resolve =
          invocation.namedArguments[#resolvePrivateDriveKey] as _Resolver;
      final beforeResolving =
          invocation.namedArguments[#beforeResolvingPrivateDrives]
              as Future<void> Function(List<DriveMetadata>)?;
      final drives = <DriveEntity, DriveKey?>{};
      final locked = <LockedDrive>[];
      await beforeResolving?.call([
        for (final drive in onChain) (tx: drive.tx, data: drive.data),
      ]);
      for (final drive in onChain) {
        final attempt = await resolve(drive.tx, drive.data);
        switch (PrivateDriveVerdict.of(attempt)) {
          case PrivateDriveVerdict.readable:
            drives[attempt.entity!] = attempt.key;
          case PrivateDriveVerdict.locked:
            locked.add(LockedDrive(
              driveId: drive.driveId,
              ownerAddress: owner,
              signatureType: DriveSignatureType.v2,
              lastUpdated: DateTime(2026),
            ));
          case PrivateDriveVerdict.skipped:
            break;
        }
      }
      if (holdDiscovery != null) {
        reachedHold.complete();
        await holdDiscovery!.future;
      }
      return UserDriveDiscovery(drives: drives, lockedDrives: locked);
    });
    when(() => arweave.cachedUserDriveCreationTimes(any())).thenReturn({});

    final configService = MockConfigService();
    when(() => configService.config).thenReturn(AppConfig(
      allowedDataItemSizeForTurbo: 0,
      stripePublishableKey: '',
    ));
    final gatewayFallback = _MockDataGatewayFallback();
    when(() => arweave.gatewayFallback).thenReturn(gatewayFallback);
    when(() => gatewayFallback.cachedGateways).thenReturn([]);

    syncRepository = SyncRepository(
      arweave: arweave,
      driveDao: db.driveDao,
      configService: configService,
      batchProcessor: _MockBatchProcessor(),
      snapshotValidationService: _MockSnapshotValidationService(),
      userPreferencesRepository: _MockUserPreferencesRepository(),
      driveUnlocker: unlocker,
    );
  });

  tearDown(() => db.close());

  Future<void> discover({
    Wallet? as,
    String password = 'login',
    bool askWalletAgain = false,
  }) =>
      syncRepository.updateUserDrives(
        wallet: as ?? wallet,
        password: password,
        cipherKey: profileKey,
        askWalletAgain: askWalletAgain,
      );

  Future<Set<String>> rows() async =>
      (await db.driveDao.allDrives().get()).map((d) => d.id).toSet();

  Set<String> lockedIds() =>
      session.currentLockedDrives.map((d) => d.driveId).toSet();

  group('keyfile wallet: k of 5 drives open with the sign-in password', () {
    for (final k in [0, 1, 2, 5]) {
      test(
          '$k of 5: $k rows, ${5 - k} locked, no throw; later passes '
          'sign nothing new', () async {
        await chain([
          for (var i = 0; i < 5; i++) i < k ? 'login' : 'other$i',
        ]);
        signer.signatures = 0; // making the fixtures signed too

        await discover();
        expect(await rows(), {for (var i = 0; i < k; i++) _id(i)});
        expect(lockedIds(), {for (var i = k; i < 5; i++) _id(i)});
        final firstPass = signer.signatures;
        expect(firstPass, 5, reason: 'one signature per drive, once');

        // Three background passes, as auto-sync or drive-list refreshes.
        for (var pass = 0; pass < 3; pass++) {
          await discover();
        }
        expect(signer.signatures, firstPass,
            reason: 'a background pass signed again');
        expect(await rows(), {for (var i = 0; i < k; i++) _id(i)});
        expect(lockedIds(), {for (var i = k; i < 5; i++) _id(i)});

        // A sync the user starts: still nothing new to sign.
        await discover(askWalletAgain: true);
        expect(signer.signatures, firstPass);
      });
    }
  });

  group('Wander (one prompt per signature, no batch): 2 of 5', () {
    test(
        'background passes after the first ask nothing; a sync the '
        'user starts asks again only for drives past the budget', () async {
      final wander = FakeWander(wallet);
      await chain(['login', 'login', 'a', 'b', 'c']);

      await discover(as: wander.wallet);
      final afterFirst = wander.prompts;
      expect(afterFirst, 3, reason: 'the per-pass budget');

      for (var pass = 0; pass < 3; pass++) {
        await discover(as: wander.wallet);
      }
      expect(wander.prompts, afterFirst, reason: 'background asked again');

      // A sync the user starts may ask again (by design), and changes
      // nothing about which drives are open.
      await discover(as: wander.wallet, askWalletAgain: true);
      expect(await rows(), {_id(0), _id(1)});
      expect(lockedIds(), {_id(2), _id(3), _id(4)});
    });
  });

  group('unlock, then the sync that follows it', () {
    test(
        'UnlockDriveCubit hands the sync exactly the drives that '
        'opened (2 of 5 share the password)', () async {
      await chain(['login', 'x', 'shared', 'shared', 'y']);
      await discover();
      expect(lockedIds(), hasLength(4));

      List<String>? synced;
      final cubit = UnlockDriveCubit(
        driveId: _id(2),
        unlocker: unlocker,
        wallet: wallet,
        profileKey: profileKey,
        syncDrives: (ids) async => synced = ids,
        signInPassword: 'login',
      );
      await cubit.submit(password: 'shared', tryOthers: true);
      expect(synced, [_id(2), _id(3)]);
      expect(lockedIds(), {_id(1), _id(4)});
      await cubit.close();
    });

    test(
        '"Try on my other locked drives" unticked: the discovery of the sync '
        'that follows leaves the other locked drives alone (sign-in password '
        'unproven)', () async {
      await chain(['right', 'shared', 'shared', 'shared', 'z']);
      // Signed in with a typo and chose Continue.
      session.setSignInPasswordProven(owner, false);
      await discover(password: 'typo');
      expect(lockedIds(), hasLength(5));

      List<String>? synced;
      final cubit = UnlockDriveCubit(
        driveId: _id(1),
        unlocker: unlocker,
        wallet: wallet,
        profileKey: profileKey,
        syncDrives: (ids) async => synced = ids,
        signInPassword: 'typo',
      );
      await cubit.submit(password: 'shared', tryOthers: false);
      expect(synced, [_id(1)]);
      expect(lockedIds(), hasLength(4), reason: 'only the one asked for');
      expect(session.provenDrivePassword(owner), isNull);

      // The sync after the unlock runs discovery first (askWalletAgain
      // false), as SyncCubit.startSync does for every sync.
      await discover(password: 'typo');

      expect(lockedIds(), {_id(0), _id(2), _id(3), _id(4)},
          reason: 'drives 2 and 3 share the password, and the person asked '
              'for drive 1 alone');
      expect(await rows(), {_id(1)});
      await cubit.close();
    });

    test('both unticked: nothing discovery runs afterwards stores a key',
        () async {
      await chain(['right', 'shared', 'shared', 'shared', 'z']);
      session.setSignInPasswordProven(owner, false);
      await discover(password: 'typo');

      final cubit = UnlockDriveCubit(
        driveId: _id(1),
        unlocker: unlocker,
        wallet: wallet,
        profileKey: profileKey,
        syncDrives: (ids) async {},
        signInPassword: 'typo',
      );
      await cubit.submit(password: 'shared', tryOthers: false, remember: false);
      await discover(password: 'typo');

      for (var i = 0; i < 5; i++) {
        expect(await db.driveDao.getStoredDriveKey(_id(i), profileKey), isNull,
            reason: 'drive $i stored');
      }
      expect(await db.driveDao.getDriveKey(_id(1), profileKey), isNotNull,
          reason: 'open this session');
      await cubit.close();
    });

    for (final remember in [true, false]) {
      test(
          'try-others ticked, "Remember on this device" '
          '${remember ? 'ticked' : 'unticked'}: a drive discovery opens later '
          'with that password is ${remember ? '' : 'not '}stored, and is open '
          'this session', () async {
        await chain(['right', 'shared', 'shared', 'z']);
        session.setSignInPasswordProven(owner, false);
        await discover(password: 'typo');

        final cubit = UnlockDriveCubit(
          driveId: _id(1),
          unlocker: unlocker,
          wallet: wallet,
          profileKey: profileKey,
          syncDrives: (ids) async {},
          signInPassword: 'typo',
        );
        await cubit.submit(
            password: 'shared', tryOthers: true, remember: remember);
        expect(lockedIds(), {_id(0), _id(3)});
        expect(session.provenDrivePassword(owner), 'shared');

        // A drive made elsewhere (the CLI, say) with the same password
        // appears on chain, and the next discovery opens it.
        final later = await makeWebPrivateDrive(
          wallet: wallet,
          driveId: _id(7),
          password: 'shared',
          name: 'Later',
          unixTime: 1700000100,
        );
        onChain.add(later);
        when(() => arweave.getEntityDataBytes(later.tx.id,
                configuredGatewayOnly: any(named: 'configuredGatewayOnly')))
            .thenAnswer((_) async => later.data);
        await discover(password: 'typo');

        expect(await rows(), containsAll([_id(1), _id(2), _id(7)]));
        expect(lockedIds(), {_id(0), _id(3)});
        expect(await db.driveDao.getDriveKey(_id(7), profileKey), isNotNull);
        expect(await db.driveDao.getStoredDriveKey(_id(7), profileKey),
            remember ? isNotNull : isNull);
        if (!remember) {
          expect(await db.driveDao.forgottenDriveIds(), contains(_id(7)),
              reason: 'the next session starts with it locked');
        }
        await cubit.close();
      });
    }

    test(
        'the same with Wander: the sync after the unlock asks '
        'Wander nothing', () async {
      final wander = FakeWander(wallet);
      await chain(['right', 'shared', 'shared', 'shared', 'z']);
      session.setSignInPasswordProven(owner, false);
      await discover(as: wander.wallet, password: 'typo');
      expect(wander.prompts, 0, reason: 'unproven: no prompts');

      final cubit = UnlockDriveCubit(
        driveId: _id(1),
        unlocker: unlocker,
        wallet: wander.wallet,
        profileKey: profileKey,
        syncDrives: (ids) async {},
        signInPassword: 'typo',
      );
      await cubit.submit(password: 'shared', tryOthers: false);
      final afterUnlock = wander.prompts;
      expect(afterUnlock, 1);

      await discover(as: wander.wallet, password: 'typo');
      // The unproven first pass asked nothing, and the password from the
      // unlock is not one discovery tries.
      expect(wander.prompts - afterUnlock, 0);
      await cubit.close();
    });
  });

  group('Wander, signed in with no password (P3)', () {
    for (final batch in [false, true]) {
      test(
          '${batch ? 'batch' : 'one by one'}: background and manual '
          'passes ask Wander nothing, every private drive is locked', () async {
        final wander = FakeWander(wallet)..batch = batch;
        await chain(['right', 'right', 'right', 'other', 'other']);
        for (var pass = 0; pass < 3; pass++) {
          await discover(as: wander.wallet, password: '');
        }
        await discover(as: wander.wallet, password: '', askWalletAgain: true);
        expect(wander.prompts, 0);
        expect(lockedIds(), hasLength(5));
        expect(await rows(), isEmpty);
      });

      test(
          '${batch ? 'batch' : 'one by one'}: after Create drive\'s "Enter '
          'your drive password", a background discovery asks Wander nothing',
          () async {
        final wander = FakeWander(wallet)..batch = batch;
        await chain(['right', 'right', 'right', 'other', 'other']);
        await discover(as: wander.wallet, password: '');
        expect(wander.prompts, 0);

        // DriveCreateCubit.submit, DrivePasswordAsk.enter.
        final failure = await unlocker.verifyDrivePassword(
          wallet: wander.wallet,
          profileKey: profileKey,
          password: 'right',
        );
        expect(failure, isNull);
        session
          ..setNewDrivePassword(owner, 'right')
          ..rememberProvenDrivePassword(owner, 'right');
        final afterCreate = wander.prompts;
        expect(afterCreate, greaterThan(0), reason: 'the person asked');

        // The next syncs nobody asked for: the login sync, a drive-list
        // refresh, or an auto-sync tick.
        for (var pass = 0; pass < 3; pass++) {
          await discover(as: wander.wallet, password: '');
        }
        expect(wander.prompts, afterCreate,
            reason: 'discovery opened a Wander window by itself');
        // The drive Create drive opened stays open; the rest wait for Unlock.
        expect(lockedIds(), isNot(contains(_id(0))));
        expect(lockedIds(), containsAll([_id(3), _id(4)]));
      });

      test(
          '${batch ? 'batch' : 'one by one'}: the password tries every drive '
          'whose signature is already held, and only those', () async {
        final wander = FakeWander(wallet)..batch = batch;
        await chain(['right', 'right', 'right', 'other', 'other']);
        await discover(as: wander.wallet, password: '');

        // Two Unlocks the person asked for, each for one drive: their
        // signatures are held now.
        for (final i in [1, 3]) {
          await unlocker.unlock(
            wallet: wander.wallet,
            profileKey: profileKey,
            driveId: _id(i),
            password: i == 1 ? 'right' : 'other',
            tryOthers: false,
          );
        }
        // Then Create drive's password check, which opens drive 0.
        await unlocker.verifyDrivePassword(
          wallet: wander.wallet,
          profileKey: profileKey,
          password: 'right',
        );
        session.rememberProvenDrivePassword(owner, 'right');
        final before = wander.prompts;

        await discover(as: wander.wallet, password: '');

        expect(wander.prompts, before);
        expect(await rows(), containsAll([_id(0), _id(1), _id(3)]));
        expect(lockedIds(), {_id(2), _id(4)});
      });
    }
  });

  group('during a running discovery', () {
    test(
        'unlock mid-pass: the drive stays unlocked and gets its row; '
        'the other locked drives are untouched', () async {
      await chain(['login', 'x', 'y', 'z', 'w']);
      await discover();

      holdDiscovery = Completer<void>();
      reachedHold = Completer<void>();
      final pass = discover();
      await reachedHold.future;
      await unlocker.unlock(
        wallet: wallet,
        profileKey: profileKey,
        driveId: _id(2),
        password: 'y',
      );
      holdDiscovery!.complete();
      await pass;

      expect(lockedIds(), {_id(1), _id(3), _id(4)});
      expect(await rows(), {_id(0), _id(2)});
    });

    test(
        'Forget mid-pass: the pass that lands after it does not '
        'store the key again', () async {
      await chain(['login', 'login', 'x', 'y', 'z']);
      await discover();
      expect(
          await db.driveDao.getStoredDriveKey(_id(1), profileKey), isNotNull);

      holdDiscovery = Completer<void>();
      reachedHold = Completer<void>();
      final pass = discover();
      await reachedHold.future;
      expect(await db.driveDao.forgetDriveKey(_id(1), profileKey), isTrue);
      holdDiscovery!.complete();
      await pass;

      expect(await db.driveDao.getStoredDriveKey(_id(1), profileKey), isNull,
          reason: 'the pass stored the forgotten key again');
      expect(await db.driveDao.forgottenDriveIds(), contains(_id(1)));
      // Still open this session, and readable by sync.
      expect(await rows(), containsAll([_id(0), _id(1)]));
      expect(await db.driveDao.getDriveKey(_id(1), profileKey), isNotNull);
      // Its sibling is untouched.
      expect(
          await db.driveDao.getStoredDriveKey(_id(0), profileKey), isNotNull);
    });

    test(
        'Forget all mid-pass: every own key forgotten stays '
        'forgotten, every drive stays open this session', () async {
      await chain(['login', 'login', 'login', 'x', 'y']);
      await discover();

      holdDiscovery = Completer<void>();
      reachedHold = Completer<void>();
      final pass = discover();
      await reachedHold.future;
      expect(
          await db.driveDao.forgetAllDriveKeys(profileKey, ownerAddress: owner),
          3);
      holdDiscovery!.complete();
      await pass;

      for (var i = 0; i < 3; i++) {
        expect(await db.driveDao.getStoredDriveKey(_id(i), profileKey), isNull);
        expect(await db.driveDao.getDriveKey(_id(i), profileKey), isNotNull);
      }
      expect(lockedIds(), {_id(3), _id(4)});
    });
  });

  group(
      'Wander that batch-signs: k of 5 drives open with the sign-in '
      'password', () {
    for (final k in [0, 1, 2, 5]) {
      test(
          '$k of 5: one approval in all, $k rows, ${5 - k} locked; later '
          'passes ask nothing', () async {
        final wander = FakeWander(wallet)..batch = true;
        await chain([
          for (var i = 0; i < 5; i++) i < k ? 'login' : 'other$i',
        ]);

        await discover(as: wander.wallet);
        expect(wander.prompts, 1);
        expect(await rows(), {for (var i = 0; i < k; i++) _id(i)});
        expect(lockedIds(), {for (var i = k; i < 5; i++) _id(i)});

        for (var pass = 0; pass < 3; pass++) {
          await discover(as: wander.wallet);
        }
        await discover(as: wander.wallet, askWalletAgain: true);
        expect(wander.prompts, 1);
        expect(await rows(), {for (var i = 0; i < k; i++) _id(i)});
      });
    }
  });

  group('Forget, then the next session', () {
    test(
        'Forget mid-pass: after a reload that drive alone is locked, the '
        'rest open from their stored keys with nothing signed', () async {
      await chain(['login', 'login', 'login', 'x', 'y']);
      await discover();

      holdDiscovery = Completer<void>();
      reachedHold = Completer<void>();
      final pass = discover();
      await reachedHold.future;
      await db.driveDao.forgetDriveKey(_id(1), profileKey);
      holdDiscovery!.complete();
      await pass;
      holdDiscovery = null;

      // A reload: memory and the session go; the database stays.
      await db.driveDao.clearSessionMemory();
      session.clear();
      await db.driveDao.detachForgottenDrives();
      signer.signatures = 0;

      await discover();

      expect(await rows(), {_id(0), _id(2)});
      expect(lockedIds(), {_id(1), _id(3), _id(4)});
      expect(signer.signatures, 2,
          reason: 'only the two drives the password never opened are signed '
              'for: the forgotten one is not tried');
    });

    test(
        'Forget all mid-pass: after a reload every own drive is locked, and '
        'the sign-in password does not open them again', () async {
      await chain(['login', 'login', 'x']);
      await discover();

      holdDiscovery = Completer<void>();
      reachedHold = Completer<void>();
      final pass = discover();
      await reachedHold.future;
      await db.driveDao.forgetAllDriveKeys(profileKey, ownerAddress: owner);
      holdDiscovery!.complete();
      await pass;
      holdDiscovery = null;

      await db.driveDao.clearSessionMemory();
      session.clear();
      await db.driveDao.detachForgottenDrives();

      await discover();

      expect(await rows(), isEmpty);
      expect(lockedIds(), {_id(0), _id(1), _id(2)});
    });
  });

  group('a private drive with a row and no key', () {
    const sharedOwner = 'someone-else';
    const sharedId = '00000000-0000-4000-8000-000000000009';

    Future<void> keylessSharedRow({int watermark = 1200}) async {
      await db.driveDao.writeDriveEntity(
        name: 'Shared',
        entity: DriveEntity(
          id: sharedId,
          name: 'Shared',
          rootFolderId: 'root-shared',
          privacy: DrivePrivacyTag.private,
        )
          ..ownerAddress = sharedOwner
          ..createdAt = DateTime(2026),
        driveKey: DriveKey(SecretKey(List.filled(32, 5)), true),
        profileKey: profileKey,
      );
      // What an older version left behind: the key gone, the row kept.
      await (db.update(db.drives)..where((d) => d.id.equals(sharedId))).write(
        DrivesCompanion(
          encryptedKey: const Value(null),
          keyEncryptionIv: const Value(null),
          lastBlockHeight: Value(watermark),
        ),
      );
    }

    Future<int?> watermark() async =>
        (await db.driveDao.driveById(driveId: sharedId).getSingle())
            .lastBlockHeight;

    test('a sync of every drive skips it and leaves its watermark', () async {
      await keylessSharedRow();
      when(() => arweave.getCurrentBlockHeight()).thenAnswer((_) async => 5000);

      final progress = await syncRepository
          .syncAllDrives(wallet: wallet, cipherKey: profileKey)
          .toList();

      expect(progress.last.failedDriveIds, isEmpty);
      expect(await watermark(), 1200);
      verifyNever(() => arweave.getCurrentBlockHeight());
    });

    test('a sync of that drive alone reads nothing for it', () async {
      await keylessSharedRow();
      when(() => arweave.getCurrentBlockHeight()).thenAnswer((_) async => 5000);

      await syncRepository
          .syncSingleDrive(
              driveId: sharedId, wallet: wallet, cipherKey: profileKey)
          .handleError((_) {})
          .toList();

      expect(await watermark(), 1200);
      verifyNever(() => arweave.getAllSnapshotsOfDrive(any(), any(),
          ownerAddress: any(named: 'ownerAddress')));
    });

    test('the next session start detaches it, so its link opens it afresh',
        () async {
      await keylessSharedRow();

      expect(await db.driveDao.detachForgottenDrives(), [sharedId]);
      expect(await db.driveDao.driveById(driveId: sharedId).getSingleOrNull(),
          isNull);
    });

    test(
        'a browser wallet replacing its old profile detaches shared drives '
        'too, rows and all', () async {
      await chain(['login', 'x']);
      await discover();
      await db.driveDao.writeDriveEntity(
        name: 'Shared',
        entity: DriveEntity(
          id: sharedId,
          name: 'Shared',
          rootFolderId: 'root-shared',
          privacy: DrivePrivacyTag.private,
        )
          ..ownerAddress = sharedOwner
          ..createdAt = DateTime(2026),
        driveKey: DriveKey(SecretKey(List.filled(32, 5)), true),
        profileKey: profileKey,
      );

      final dropped =
          await db.driveDao.discardStoredDriveKeys(ownerAddress: owner);

      expect(dropped, (own: 1, shared: 1));
      expect(await rows(), isEmpty);
    });
  });
}
