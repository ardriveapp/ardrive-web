import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

/// A drive's activity, for a drive this device has never synced.
///
/// Its history is stored only by a sync, so the tab used to wait on it for
/// good. It now reads the drive's own revisions from the network and shows
/// them, without storing them, so a later sync starts where it would have.
void main() {
  const driveId = 'drive';
  const rootFolderId = 'root';
  const ownerAddress = 'owner';

  late Database db;
  late DriveDao driveDao;
  late MockArweaveService arweave;
  late MockProfileCubit profileCubit;

  final profileKey = SecretKey(List.filled(32, 7));
  final driveKey = DriveKey(SecretKey(List.filled(32, 9)), true);

  DriveEntity revision({
    required String txId,
    required String name,
    required DateTime at,
    bool isHidden = false,
    String privacy = DrivePrivacyTag.public,
  }) =>
      DriveEntity(
        id: driveId,
        name: name,
        rootFolderId: rootFolderId,
        privacy: privacy,
        authMode: privacy == DrivePrivacyTag.private
            ? DriveAuthModeTag.password
            : DriveAuthModeTag.none,
        isHidden: isHidden,
      )
        ..ownerAddress = ownerAddress
        ..txId = txId
        ..createdAt = at;

  /// What reading the drive list leaves behind: the drive, and no revisions.
  Future<void> discoverDrive({String privacy = DrivePrivacyTag.public}) =>
      driveDao.updateUserDrives(
        {
          revision(
            txId: 'latest',
            name: 'Photos',
            at: DateTime(2026, 3, 1),
            privacy: privacy,
          ): privacy == DrivePrivacyTag.private ? driveKey : null,
        },
        profileKey,
      );

  /// The drive's creation as a sync records it.
  Future<void> recordSyncedHistory() async {
    await db.into(db.networkTransactions).insert(
          NetworkTransactionsCompanion.insert(
            id: 'synced-tx',
            dateCreated: Value(DateTime(2025, 1, 1)),
          ),
        );
    await db.into(db.driveRevisions).insert(
          DriveRevisionsCompanion.insert(
            driveId: driveId,
            rootFolderId: rootFolderId,
            ownerAddress: ownerAddress,
            name: 'Photos',
            privacy: DrivePrivacyTag.public,
            metadataTxId: 'synced-tx',
            action: RevisionAction.create,
            dateCreated: Value(DateTime(2025, 1, 1)),
          ),
        );
  }

  void logIn() => when(() => profileCubit.state).thenReturn(
        ProfileLoggedIn(
          user: User(
            password: 'password',
            wallet: getTestWallet(),
            walletAddress: ownerAddress,
            walletBalance: BigInt.one,
            cipherKey: profileKey,
            profileType: ProfileType.json,
            errorFetchingIOTokens: false,
          ),
          useTurbo: false,
        ),
      );

  void networkAnswers(Future<List<DriveEntity>?> Function() answer) => when(
        () => arweave.getDriveEntityRevisions(
          any(),
          ownerAddress: any(named: 'ownerAddress'),
          driveKey: any(named: 'driveKey'),
          isCancelled: any(named: 'isCancelled'),
        ),
      ).thenAnswer((_) => answer());

  FsEntryActivityCubit cubitFor(Drive drive) => FsEntryActivityCubit(
        driveId: driveId,
        maybeSelectedItem:
            DriveDataTableItemMapper.fromDrive(drive, (_) {}, 0, true),
        driveDao: driveDao,
        arweave: arweave,
        profileCubit: profileCubit,
      );

  /// The first state after the initial one that is not still loading.
  Future<FsEntryActivityState> settled(FsEntryActivityCubit cubit) =>
      cubit.stream.firstWhere((s) => s is! FsEntryActivityInitial);

  setUpAll(() {
    registerFallbackValue(SecretKey([]));
  });

  setUp(() {
    db = getTestDb();
    driveDao = db.driveDao;
    arweave = MockArweaveService();
    profileCubit = MockProfileCubit();
    logIn();
  });

  tearDown(() => db.close());

  test('shows an unsynced drive its history from the network, newest first',
      () async {
    await discoverDrive();
    networkAnswers(() async => [
          revision(txId: 'a', name: 'Photos', at: DateTime(2025, 1, 1)),
          revision(txId: 'b', name: 'Pics', at: DateTime(2025, 6, 1)),
          revision(
            txId: 'c',
            name: 'Pics',
            at: DateTime(2026, 3, 1),
            isHidden: true,
          ),
        ]);

    final drive = await driveDao.driveById(driveId: driveId).getSingle();
    final cubit = cubitFor(drive);
    final state = await settled(cubit);

    expect(state, isA<FsEntryActivitySuccess<DriveRevisionsCompanion>>());
    final revisions =
        (state as FsEntryActivitySuccess<DriveRevisionsCompanion>).revisions;
    expect(
      revisions.map((r) => r.action.value),
      [RevisionAction.hide, RevisionAction.rename, RevisionAction.create],
    );
    expect(revisions.map((r) => r.name.value), ['Pics', 'Pics', 'Photos']);
    expect(revisions.last.dateCreated.value, DateTime(2025, 1, 1));

    await cubit.close();
  });

  test('asks for the drive by its owner, with no key for a public drive',
      () async {
    await discoverDrive();
    networkAnswers(() async => []);

    final drive = await driveDao.driveById(driveId: driveId).getSingle();
    final cubit = cubitFor(drive);
    await settled(cubit);

    verify(
      () => arweave.getDriveEntityRevisions(
        driveId,
        ownerAddress: ownerAddress,
        driveKey: null,
        isCancelled: any(named: 'isCancelled'),
      ),
    ).called(1);

    await cubit.close();
  });

  /// The point of the read being a read: the drive is exactly as unsynced
  /// afterwards as before, and the next sync finds nothing it has to skip.
  test('stores nothing it reads', () async {
    await discoverDrive();
    networkAnswers(() async => [
          revision(txId: 'a', name: 'Photos', at: DateTime(2025, 1, 1)),
          revision(txId: 'b', name: 'Pics', at: DateTime(2025, 6, 1)),
        ]);

    final before = await driveDao.driveById(driveId: driveId).getSingle();
    final cubit = cubitFor(before);
    await settled(cubit);
    await cubit.close();

    expect(await db.select(db.driveRevisions).get(), isEmpty);
    expect(await db.select(db.networkTransactions).get(), isEmpty);
    expect(await db.select(db.folderRevisions).get(), isEmpty);

    final after = await driveDao.driveById(driveId: driveId).getSingle();
    expect(after, before);
  });

  test('says to sync when the history could not be read', () async {
    await discoverDrive();
    networkAnswers(() async => null);

    final drive = await driveDao.driveById(driveId: driveId).getSingle();
    final cubit = cubitFor(drive);

    expect(await settled(cubit), isA<FsEntryActivityDriveNotSynced>());

    await cubit.close();
  });

  test('says to sync when the network has no history for it', () async {
    await discoverDrive();
    networkAnswers(() async => []);

    final drive = await driveDao.driveById(driveId: driveId).getSingle();
    final cubit = cubitFor(drive);

    expect(await settled(cubit), isA<FsEntryActivityDriveNotSynced>());

    await cubit.close();
  });

  test('says to sync when the read throws', () async {
    await discoverDrive();
    networkAnswers(() async => throw Exception('gateway down'));

    final drive = await driveDao.driveById(driveId: driveId).getSingle();
    final cubit = cubitFor(drive);

    expect(await settled(cubit), isA<FsEntryActivityDriveNotSynced>());

    await cubit.close();
  });

  test('shows a synced drive its own history and reads nothing', () async {
    await discoverDrive();
    await recordSyncedHistory();
    networkAnswers(() async => []);

    final drive = await driveDao.driveById(driveId: driveId).getSingle();
    final cubit = cubitFor(drive);
    final state = await settled(cubit);

    expect(state, isA<FsEntryActivitySuccess<DriveRevisionWithTransaction>>());
    verifyNever(
      () => arweave.getDriveEntityRevisions(
        any(),
        ownerAddress: any(named: 'ownerAddress'),
        driveKey: any(named: 'driveKey'),
        isCancelled: any(named: 'isCancelled'),
      ),
    );

    await cubit.close();
  });

  /// A sync that lands while the read is out has the real history. The read
  /// finishing afterwards must not put its copy back over it.
  test('drops the network history once a sync has recorded the real one',
      () async {
    await discoverDrive();
    final answer = Completer<List<DriveEntity>?>();
    networkAnswers(() => answer.future);

    final drive = await driveDao.driveById(driveId: driveId).getSingle();
    final cubit = cubitFor(drive);
    final states = <FsEntryActivityState>[];
    final subscription = cubit.stream.listen(states.add);

    // Wait for the read to be asked for.
    await untilCalled(
      () => arweave.getDriveEntityRevisions(
        any(),
        ownerAddress: any(named: 'ownerAddress'),
        driveKey: any(named: 'driveKey'),
        isCancelled: any(named: 'isCancelled'),
      ),
    );

    await recordSyncedHistory();
    await cubit.stream
        .firstWhere((s) => s is FsEntryActivitySuccess)
        .timeout(const Duration(seconds: 5));

    answer.complete([
      revision(txId: 'a', name: 'Old name', at: DateTime(2024, 1, 1)),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(states.last,
        isA<FsEntryActivitySuccess<DriveRevisionWithTransaction>>());
    expect(
      states.whereType<FsEntryActivitySuccess<DriveRevisionsCompanion>>(),
      isEmpty,
    );

    await subscription.cancel();
    await cubit.close();
  });

  /// The reads still to start are not made for a panel nobody is looking at.
  test('tells the read to stop once the panel is closed', () async {
    await discoverDrive();
    final answer = Completer<List<DriveEntity>?>();
    networkAnswers(() => answer.future);

    final drive = await driveDao.driveById(driveId: driveId).getSingle();
    final cubit = cubitFor(drive);

    await untilCalled(
      () => arweave.getDriveEntityRevisions(
        any(),
        ownerAddress: any(named: 'ownerAddress'),
        driveKey: any(named: 'driveKey'),
        isCancelled: any(named: 'isCancelled'),
      ),
    );
    final isCancelled = verify(
      () => arweave.getDriveEntityRevisions(
        any(),
        ownerAddress: any(named: 'ownerAddress'),
        driveKey: any(named: 'driveKey'),
        isCancelled: captureAny(named: 'isCancelled'),
      ),
    ).captured.single as bool Function();

    expect(isCancelled(), isFalse);
    await cubit.close();
    expect(isCancelled(), isTrue);

    answer.complete(null);
  });

  group('a private drive', () {
    test('is read with its own key, unlocked with the profile key', () async {
      await discoverDrive(privacy: DrivePrivacyTag.private);
      networkAnswers(() async => []);

      final drive = await driveDao.driveById(driveId: driveId).getSingle();
      final cubit = cubitFor(drive);
      await settled(cubit);

      final captured = verify(
        () => arweave.getDriveEntityRevisions(
          driveId,
          ownerAddress: ownerAddress,
          driveKey: captureAny(named: 'driveKey'),
          isCancelled: any(named: 'isCancelled'),
        ),
      ).captured;

      final key = captured.single as SecretKey;
      expect(await key.extractBytes(), await driveKey.key.extractBytes());

      await cubit.close();
    });

    /// A private drive's revisions without its key decrypt to nothing, so
    /// there is nothing to ask for.
    test('without its key is not read, and says to sync', () async {
      await discoverDrive(privacy: DrivePrivacyTag.private);
      // Logged out, and the key is not held in memory either.
      when(() => profileCubit.state).thenReturn(ProfilePromptLogIn());
      networkAnswers(() async => []);

      final drive = await driveDao.driveById(driveId: driveId).getSingle();
      final cubit = cubitFor(drive);

      expect(await settled(cubit), isA<FsEntryActivityDriveNotSynced>());
      verifyNever(
        () => arweave.getDriveEntityRevisions(
          any(),
          ownerAddress: any(named: 'ownerAddress'),
          driveKey: any(named: 'driveKey'),
          isCancelled: any(named: 'isCancelled'),
        ),
      );

      await cubit.close();
    });
  });
}
