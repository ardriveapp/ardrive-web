import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

void main() {
  const driveId = 'a2b7ba0a-3b2a-4c1b-8a2f-6d1a0b3c4d5e';
  const rootFolderId = 'b3c8cb1b-4c3b-5d2c-9b3f-7e2b1c4d5e6f';
  const ownerAddress = 'fOVzBRTBnyt4VrUUYadBH8yras_-jhgpmNgg-5b3vEw';

  late Database db;
  late DriveDao driveDao;
  late MockProfileCubit profileCubit;

  final profileKey = SecretKey(List.filled(32, 1));
  final driveKey = DriveKey(SecretKey(List.filled(32, 2)), true);

  /// Writes the drive row itself, with no encrypted key attached - which is
  /// what [DriveDao.getDriveKey] reads to decide there is no key.
  Future<void> insertDrive({required bool isPrivate}) =>
      db.into(db.drives).insert(
            DrivesCompanion.insert(
              id: driveId,
              name: 'My Drive',
              ownerAddress: ownerAddress,
              rootFolderId: rootFolderId,
              privacy: isPrivate
                  ? DrivePrivacyTag.private
                  : DrivePrivacyTag.public,
              lastBlockHeight: const Value(1),
            ),
          );

  Future<Drive> drive() => driveDao.driveById(driveId: driveId).getSingle();

  DriveShareCubit cubit(Drive d, {String? folderId}) => DriveShareCubit(
        drive: d,
        folderId: folderId,
        driveDao: driveDao,
        profileCubit: profileCubit,
      );

  /// The cubit's first settled state.
  ///
  /// Checks [Cubit.state] before the stream because the public path is
  /// entirely synchronous - the link needs no await, so the success is emitted
  /// from the constructor before any listener can attach, and a cubit stream
  /// does not replay.
  Future<DriveShareState> settled(DriveShareCubit c) async {
    if (c.state is! DriveShareLoadInProgress) {
      return c.state;
    }

    return c.stream
        .firstWhere((s) => s is! DriveShareLoadInProgress)
        .timeout(const Duration(seconds: 5));
  }

  void signedIn() => when(() => profileCubit.state).thenReturn(
        ProfileLoggedIn(
          user: User(
            password: 'password',
            wallet: getTestWallet(),
            walletAddress: ownerAddress,
            walletBalance: BigInt.one,
            cipherKey: profileKey,
            profileType: ProfileType.json,
            ioTokens: 'ioTokens',
            errorFetchingIOTokens: false,
          ),
          useTurbo: false,
        ),
      );

  setUp(() {
    db = getTestDb();
    driveDao = db.driveDao;
    profileCubit = MockProfileCubit();
    signedIn();
  });

  tearDown(() async => db.close());

  group('DriveShareCubit', () {
    test('a public drive resolves to a link with no key in it', () async {
      await insertDrive(isPrivate: false);

      final state = await settled(cubit(await drive()));

      expect(state, isA<DriveShareLoadSuccess>());

      final link = (state as DriveShareLoadSuccess).driveShareLink.toString();

      expect(link, contains('/#/drives/$driveId'));
      expect(link, isNot(contains('driveKey')));
    });

    test(
        'a private drive with no reachable key fails instead of hanging - '
        'the dialog used to spin forever on an unhandled StateError', () async {
      // The drive row exists but carries no encrypted key, so `getDriveKey`
      // returns null and the cubit throws `StateError('Drive key not found')`.
      // That throw happens inside a future started from the constructor and
      // never awaited: before the guard nothing caught it, the cubit stayed in
      // `DriveShareLoadInProgress`, and the dialog showed a spinner with no
      // way out. The timeout above is what makes "hangs" a failure rather than
      // a hung test run.
      await insertDrive(isPrivate: true);

      expect(await settled(cubit(await drive())), isA<DriveShareLoadFail>());
    });

    test('a failure from the database is caught too', () async {
      // No drive row at all, so `getDriveKey` throws out of `getSingle()`
      // rather than returning null. The guard has to cover the unexpected
      // failure as well as the expected one.
      await insertDrive(isPrivate: true);

      final d = await drive();

      await db.delete(db.drives).go();

      expect(await settled(cubit(d)), isA<DriveShareLoadFail>());
    });

    test('a failed load can be retried', () async {
      await insertDrive(isPrivate: true);

      final c = cubit(await drive());

      await c.stream.firstWhere((s) => s is DriveShareLoadFail);

      // Retry is the point of the failure state: the key may become reachable
      // once the profile has finished loading. The expectation is armed before
      // the call so that neither emission can be missed.
      final expectation = expectLater(
        c.stream,
        emitsInOrder([
          isA<DriveShareLoadInProgress>(),
          isA<DriveShareLoadFail>(),
        ]),
      );

      await c.loadDriveShareDetails();
      await expectation;
    });

    test('a private drive link is keyless by default', () async {
      // A drive key opens every file in the drive, for the life of the drive,
      // and cannot be rotated. It is handed over as its own artifact unless
      // the sharer deliberately embeds it.
      when(() => profileCubit.state).thenReturn(ProfilePromptAdd());

      await insertDrive(isPrivate: true);
      await driveDao.putDriveKeyInMemory(driveID: driveId, driveKey: driveKey);

      final state = await settled(cubit(await drive()));

      expect(state, isA<DriveShareLoadSuccess>());

      final success = state as DriveShareLoadSuccess;

      expect(success.driveShareLink.toString(), isNot(contains('driveKey')));
      expect(success.keyIsInLink, isFalse);
      // The key is still offered, just not inside the link.
      expect(success.hasSeparateKeyArtifact, isTrue);
      expect(success.driveKeyBase64, isNotNull);
    });

    test('opting in embeds the key and retires the separate artifact',
        () async {
      when(() => profileCubit.state).thenReturn(ProfilePromptAdd());

      await insertDrive(isPrivate: true);
      await driveDao.putDriveKeyInMemory(driveID: driveId, driveKey: driveKey);

      final c = cubit(await drive());

      await settled(c);
      await c.setKeyIsInLink(true);

      final success = c.state as DriveShareLoadSuccess;

      expect(success.driveShareLink.toString(), contains('driveKey='));
      expect(success.keyIsInLink, isTrue);
      expect(success.hasSeparateKeyArtifact, isFalse);
    });

    test('a public drive has no key artifact to offer', () async {
      await insertDrive(isPrivate: false);

      final success = await settled(cubit(await drive()))
          as DriveShareLoadSuccess;

      expect(success.driveKeyBase64, isNull);
      expect(success.hasSeparateKeyArtifact, isFalse);
    });

    test('a folder link names the folder inside the drive', () async {
      const folderId = 'c4d9dc2c-5d4c-6e3d-ac4f-8f3c2d5e6f70';

      await insertDrive(isPrivate: false);

      final success =
          await settled(cubit(await drive(), folderId: folderId))
              as DriveShareLoadSuccess;

      expect(
        success.driveShareLink.toString(),
        contains('/#/drives/$driveId/folders/$folderId'),
      );
      expect(success.isFolder, isTrue);
    });

    test('a private folder link can carry the drive key when opted in',
        () async {
      const folderId = 'c4d9dc2c-5d4c-6e3d-ac4f-8f3c2d5e6f70';

      when(() => profileCubit.state).thenReturn(ProfilePromptAdd());

      await insertDrive(isPrivate: true);
      await driveDao.putDriveKeyInMemory(driveID: driveId, driveKey: driveKey);

      final c = cubit(await drive(), folderId: folderId);

      await settled(c);
      await c.setKeyIsInLink(true);

      final link = (c.state as DriveShareLoadSuccess).driveShareLink.toString();

      // Both halves have to survive together: the parser used to return the
      // drive route as soon as it saw a key, which lost the folder.
      expect(link, contains('/folders/$folderId'));
      expect(link, contains('driveKey='));
    });

    test('a private drive resolves to a link carrying its key', () async {
      // Signed out, so the key comes from the in-memory vault - the path a
      // drive attached this session but never persisted takes.
      when(() => profileCubit.state).thenReturn(ProfilePromptAdd());

      await insertDrive(isPrivate: true);
      await driveDao.putDriveKeyInMemory(
        driveID: driveId,
        driveKey: driveKey,
      );

      final c = cubit(await drive());

      await settled(c);
      await c.setKeyIsInLink(true);

      expect(
        (c.state as DriveShareLoadSuccess).driveShareLink.toString(),
        contains('driveKey='),
      );
    });
  });
}
