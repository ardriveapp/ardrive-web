import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart'
    show DrivePrivacy;
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/user.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/locked_drive_fixtures.dart';
import '../test_utils/utils.dart';

/// A browser wallet whose drive signature isn't the deterministic one (a
/// hardware wallet such as Keystone adds an anchor of its own) can't make a
/// private drive anyone could open again, so none is made.
void main() {
  late Database db;
  late MockProfileCubit profileCubit;
  late MockDrivesCubit drivesCubit;
  late FakeWander wander;

  setUpAll(() => registerFallbackValue(getTestWallet()));

  setUp(() async {
    db = getTestDb();
    profileCubit = MockProfileCubit();
    drivesCubit = MockDrivesCubit();
    final jwk = getTestWallet();
    wander = FakeWander(jwk);

    when(() => drivesCubit.state).thenReturn(DrivesLoadInProgress());
    when(() => profileCubit.logoutIfWalletMismatch())
        .thenAnswer((_) async => false);
    when(() => profileCubit.state).thenReturn(ProfileLoggedIn(
      user: User(
        password: 'drive password',
        wallet: wander.wallet,
        walletAddress: await jwk.getAddress(),
        walletBalance: BigInt.from(10000001),
        cipherKey: SecretKey(List.filled(32, 1)),
        profileType: ProfileType.arConnect,
        errorFetchingIOTokens: false,
      ),
      useTurbo: false,
    ));
  });

  tearDown(() => db.close());

  DriveCreateCubit cubit() => DriveCreateCubit(
        arweave: MockArweaveService(),
        turboUploadService: DontUseUploadService(),
        driveDao: db.driveDao,
        profileCubit: profileCubit,
        drivesCubit: drivesCubit,
        privacy: DrivePrivacy.private,
      );

  test(
      'a signature no drive key can come from: the private drive is refused '
      'with its own message, and nothing is made', () async {
    wander.varyV2 = true;
    final create = cubit();

    await create.submit('Secrets');

    final state = create.state;
    expect(state, isA<DriveCreateFailure>());
    expect((state as DriveCreateFailure).walletCantMakeDriveKeys, isTrue);
    expect(await db.driveDao.allDrives().get(), isEmpty);
    expect(wander.prompts, 1);
  });

  test('a deterministic signature is not refused', () async {
    final create = cubit();

    await create.submit('Secrets');

    // It gets past the key (the mocked network stops it later).
    final state = create.state;
    expect(
      state is DriveCreateFailure && state.walletCantMakeDriveKeys,
      isFalse,
    );
  });
}
