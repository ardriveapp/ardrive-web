import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/locked_drives/domain/drive_unlock_session.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/locked_drives/domain/locked_drive.dart';
import 'package:ardrive/locked_drives/domain/user_drive_discovery.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/search/search_result.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/sync/data/snapshot_validation_service.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/utils/batch_processor.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/locked_drive_fixtures.dart';
import '../test_utils/utils.dart';

class _MockDataGatewayFallback extends Mock implements DataGatewayFallback {}

class MockBatchProcessor extends Mock implements BatchProcessor {}

class MockSnapshotValidationService extends Mock
    implements SnapshotValidationService {}

class MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

const _opens = '6939b9e0-cc98-42cb-bae0-5888eca78885';
const _locked = '2c1d4b5e-0f3a-4c8b-9d7e-6a5b4c3d2e1f';

typedef _Resolver = Future<DriveKeyAttempt> Function(
    TransactionCommonMixin driveTx, Uint8List data);

/// Drive discovery end to end with real drive keys and a real database, the
/// gateway alone mocked: what becomes a row, what is listed as locked, and
/// what the wallet is asked.
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

  /// When set, discovery holds its answer until it completes, and says when
  /// it has got there through [reachedHold].
  Completer<void>? holdDiscovery;
  late Completer<void> reachedHold;
  final profileKey = SecretKey(List.filled(32, 9));

  setUpAll(() {
    registerFallbackValue(getTestWallet());
    registerFallbackValue((TransactionCommonMixin tx, Uint8List data) async =>
        const DriveKeyAttempt.failed(DriveUnlockFailure.unavailable));
  });

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

    onChain = [
      await makeWebPrivateDrive(
          wallet: wallet, driveId: _opens, password: 'login', name: 'Mine'),
      await makeWebPrivateDrive(
          wallet: wallet, driveId: _locked, password: 'cli', name: 'Secret'),
    ];

    // Discovery as ArweaveService runs it: each private drive through the
    // resolver it is handed, sorted by the verdict.
    when(() => arweave.getUniqueUserDriveEntities(
          any(),
          any(),
          onDriveRead: any(named: 'onDriveRead'),
          onDriveUnlocked: any(named: 'onDriveUnlocked'),
          resolvePrivateDriveKey: any(named: 'resolvePrivateDriveKey'),
        )).thenAnswer((invocation) async {
      final resolve =
          invocation.namedArguments[#resolvePrivateDriveKey] as _Resolver;
      final drives = <DriveEntity, DriveKey?>{};
      final locked = <LockedDrive>[];

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
    for (final drive in onChain) {
      when(() => arweave.getLatestDriveTx(drive.driveId, owner,
              maxRetries: any(named: 'maxRetries')))
          .thenAnswer((_) async => drive.tx);
      when(() => arweave.getEntityDataBytes(drive.tx.id,
              configuredGatewayOnly: any(named: 'configuredGatewayOnly')))
          .thenAnswer((_) async => drive.data);
    }

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
      batchProcessor: MockBatchProcessor(),
      snapshotValidationService: MockSnapshotValidationService(),
      userPreferencesRepository: MockUserPreferencesRepository(),
      driveUnlocker: unlocker,
    );
  });

  tearDown(() => db.close());

  Future<void> discover({bool askWalletAgain = false}) =>
      syncRepository.updateUserDrives(
        wallet: wallet,
        password: 'login',
        cipherKey: profileKey,
        askWalletAgain: askWalletAgain,
      );

  test(
      'a drive the sign-in password opens gets a row; one it doesn\'t is '
      'listed as locked and gets nothing: no row, no root folder, nothing to '
      'search, export, snapshot, fix or migrate', () async {
    await discover();

    final rows = await db.driveDao.allDrives().get();
    expect(rows.map((d) => d.id), [_opens]);
    expect(rows.single.name, 'Mine');

    expect(session.currentLockedDrives.map((d) => d.driveId), [_locked]);

    // Every reader of a drive starts from its row or its folders.
    expect(await db.driveDao.driveById(driveId: _locked).getSingleOrNull(),
        isNull);
    expect(
      (await db.select(db.folderEntries).get())
          .where((f) => f.driveId == _locked),
      isEmpty,
    );
    expect(await db.driveDao.ghostFolders().get(), isEmpty);
    expect(
      await db.driveDao
          .search(query: 'Private drive', type: SearchQueryType.all),
      isEmpty,
    );
    expect(await db.driveDao.getDriveKeyFromMemory(_locked), isNull);
  });

  test(
      'a drive unlocked with its own password opens on the next pass from '
      'the key this device stored, without asking the wallet', () async {
    await discover();
    await unlocker.unlock(
      wallet: wallet,
      profileKey: profileKey,
      driveId: _locked,
      password: 'cli',
    );

    // A reload: memory is gone, the database stays.
    await db.driveDao.clearSessionMemory();
    final reloaded = DriveUnlockSession();
    syncRepository = SyncRepository(
      arweave: arweave,
      driveDao: db.driveDao,
      configService: MockConfigService(),
      batchProcessor: MockBatchProcessor(),
      snapshotValidationService: MockSnapshotValidationService(),
      userPreferencesRepository: MockUserPreferencesRepository(),
      driveUnlocker: DriveUnlocker(
        crypto: ArDriveCrypto(),
        arweave: arweave,
        driveDao: db.driveDao,
        session: reloaded,
      ),
    );
    signer.signatures = 0;

    await discover();

    expect(reloaded.currentLockedDrives, isEmpty);
    expect((await db.driveDao.allDrives().get()).map((d) => d.id).toSet(),
        {_opens, _locked});
    expect(signer.signatures, 0);
  });

  test(
      'one drive\'s cancelled wallet prompt leaves that drive locked and the '
      'rest syncing; a background pass does not ask again, a sync the user '
      'started does', () async {
    // The first drive's signature is already held this session; only the
    // second needs the wallet, and the user cancels it.
    final opensSignature = await ArDriveCrypto()
        .walletSignatureForDrive(wallet, _opens, DriveSignatureType.v2);
    session.rememberSignature(
        owner, _opens, DriveSignatureType.v2, opensSignature);
    onChain = [
      onChain[0],
      await makeWebPrivateDrive(
          wallet: wallet, driveId: _locked, password: 'login', name: 'Two'),
    ];
    signer
      ..signatures = 0
      ..refuse = true;

    await discover();

    expect((await db.driveDao.allDrives().get()).map((d) => d.id), [_opens]);
    expect(session.isLocked(_locked), isTrue);
    expect(signer.signatures, 1);

    await discover();
    expect(signer.signatures, 1, reason: 'a background pass asked again');

    signer.refuse = false;
    await discover(askWalletAgain: true);

    expect(signer.signatures, 2);
    expect(session.isLocked(_locked), isFalse);
    expect((await db.driveDao.allDrives().get()).map((d) => d.id).toSet(),
        {_opens, _locked});
  });

  test(
      'a drive unlocked while a discovery pass runs is not locked again by '
      'that pass', () async {
    // The pass reads the drive as locked; the user unlocks it before the
    // pass writes its answer.
    holdDiscovery = Completer<void>();
    reachedHold = Completer<void>();
    final sync = discover();
    await reachedHold.future;
    await unlocker.unlock(
      wallet: wallet,
      profileKey: profileKey,
      driveId: _locked,
      password: 'cli',
    );
    holdDiscovery!.complete();
    await sync;

    expect(session.isLocked(_locked), isFalse);
  });

  test(
      'after sign-in, a wallet that prompts is asked at most 3 times per '
      'pass, and the drives left over are not asked by later passes', () async {
    final wander = FakeWander(wallet);
    onChain = [
      for (var i = 0; i < 6; i++)
        await makeWebPrivateDrive(
          wallet: wallet,
          driveId: '00000000-0000-4000-8000-00000000000$i',
          password: 'cli',
        ),
    ];

    Future<void> discoverWith({bool askWalletAgain = false}) =>
        syncRepository.updateUserDrives(
          wallet: wander.wallet,
          password: 'login',
          cipherKey: profileKey,
          askWalletAgain: askWalletAgain,
        );

    await discoverWith();
    expect(wander.prompts, 3);
    expect(session.currentLockedDrives, hasLength(6));

    await discoverWith();
    expect(wander.prompts, 3, reason: 'a background pass asked again');

    await discoverWith(askWalletAgain: true);
    expect(wander.prompts, 6, reason: 'a sync the user started may ask');
  });

  test('syncing one drive asks again for that drive and no other', () async {
    session
      ..markWalletDeclined(owner, _opens)
      ..markWalletDeclined(owner, _locked);

    await syncRepository.updateUserDrives(
      wallet: wallet,
      password: 'login',
      cipherKey: profileKey,
      askWalletAgainFor: [_opens],
    );

    expect(session.walletDeclined(owner, _opens), isFalse);
    expect(session.isLocked(_opens), isFalse);
    expect(session.walletDeclined(owner, _locked), isTrue);
  });
}
