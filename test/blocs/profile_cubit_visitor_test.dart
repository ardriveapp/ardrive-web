import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Selectable;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

class _MockSelectable<T> extends Mock implements Selectable<T> {}

/// What a visitor leaves in the database, and what sign-in does with it, on
/// a real database: a drive opened without a profile, its key in memory only.
void main() {
  const driveId = 'b3c8cb1b-4c3b-5d2c-9b3f-7e2b1c4d5e6f';
  const rootFolderId = 'e6fbfe4e-7f6e-8a5f-ce6f-af5e4f7a8b92';

  late Database db;
  late MockArDriveAuth auth;
  late StreamController<User?> authUsers;
  ProfileCubit? cubit;

  final visitorKey = DriveKey(SecretKey(List.filled(32, 3)), true);
  final profileKey = SecretKey(List.filled(32, 7));

  Future<void> insertPrivateDrive() =>
      db.into(db.drives).insert(DrivesCompanion.insert(
            id: driveId,
            rootFolderId: rootFolderId,
            ownerAddress: 'someone-else',
            name: 'a shared drive',
            privacy: DrivePrivacyTag.private,
          ));

  ProfileCubit buildCubit() {
    final profileDao = MockProfileDao();
    final noStoredProfile = _MockSelectable<Profile>();
    when(() => noStoredProfile.getSingleOrNull()).thenAnswer((_) async => null);
    when(() => profileDao.defaultProfile()).thenReturn(noStoredProfile);

    final turboUploadService = MockTurboUploadService();
    when(() => turboUploadService.useTurboUpload).thenReturn(true);

    return ProfileCubit(
      turboUploadService: turboUploadService,
      profileDao: profileDao,
      db: db,
      tabVisibilitySingleton: TabVisibilitySingleton(),
      arDriveAuth: auth,
    );
  }

  setUp(() {
    db = getTestDb();
    auth = MockArDriveAuth();
    authUsers = StreamController<User?>.broadcast();
    when(() => auth.onAuthStateChanged()).thenAnswer((_) => authUsers.stream);
    when(() => auth.currentUser)
        .thenThrow(const AuthenticationUserIsNotLoggedInException());
  });

  tearDown(() async {
    await cubit?.close();
    cubit = null;
    await authUsers.close();
    await db.close();
  });

  test('a start with no profile forgets the drives an earlier visitor opened',
      () async {
    await insertPrivateDrive();

    cubit = buildCubit();
    await expectLater(
      cubit!.stream,
      emits(isA<ProfilePromptAdd>()),
    );

    expect(await db.driveDao.allDrives().get(), isEmpty);
  });

  test(
      'signing in stores the key of a drive opened as a visitor before '
      'announcing the login', () async {
    cubit = buildCubit();
    await expectLater(cubit!.stream, emits(isA<ProfilePromptAdd>()));

    // Opened now, after the start: this is the drive being carried in.
    await insertPrivateDrive();
    await db.driveDao.putDriveKeyInMemory(
      driveID: driveId,
      driveKey: visitorKey,
    );

    List<int>? keyOnRowAtLogin;
    final seen = cubit!.stream.listen((state) async {
      if (state is ProfileLoggedIn) {
        keyOnRowAtLogin =
            (await db.driveDao.driveById(driveId: driveId).getSingle())
                .encryptedKey;
      }
    });

    await cubit!.unlockDefaultProfile(
      User(
        password: 'password',
        wallet: getTestWallet(),
        walletAddress: 'wallet-address',
        walletBalance: BigInt.zero,
        cipherKey: profileKey,
        profileType: ProfileType.json,
        errorFetchingIOTokens: false,
      ),
      ProfileType.json,
    );
    await pumpEventQueue();
    await seen.cancel();

    expect(keyOnRowAtLogin, isNotNull);

    final stored = await db.driveDao.getDriveKey(driveId, profileKey);
    expect(
      await stored!.key.extractBytes(),
      await visitorKey.key.extractBytes(),
    );
  });
}
