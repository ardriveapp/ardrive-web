@Tags(['broken'])

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';
import 'package:drift/drift.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/fakes.dart';
import '../test_utils/utils.dart';

void main() {
  group('DriveCreateCubit', () {
    late Database db;
    late DriveDao driveDao;

    late ArweaveService arweave;
    late DrivesCubit drivesCubit;
    late ProfileCubit profileCubit;
    late DriveCreateCubit driveCreateCubit;

    const validDriveName = 'valid-drive-name';

    setUp(() async {
      registerFallbackValue(DrivesStateFake());
      registerFallbackValue(ProfileStateFake());

      db = getTestDb();
      driveDao = db.driveDao;
      final configService = ConfigService();
      final config = await configService.getConfig(
        localStore: await LocalKeyValueStore.getInstance(),
      );

      arweave = ArweaveService(
          Arweave(gatewayUrl: Uri.parse(config.defaultArweaveGatewayUrl!)));
      drivesCubit = MockDrivesCubit();
      profileCubit = MockProfileCubit();

      final wallet = getTestWallet();
      final walletAddress = await wallet.getAddress();

      final keyBytes = Uint8List(32);
      fillBytesWithSecureRandom(keyBytes);

      when(() => profileCubit.state).thenReturn(
        ProfileLoggedIn(
          username: 'Test',
          password: '123',
          wallet: wallet,
          walletAddress: walletAddress,
          walletBalance: BigInt.one,
          cipherKey: SecretKey(keyBytes),
        ),
      );

      driveCreateCubit = DriveCreateCubit(
        arweave: arweave,
        driveDao: driveDao,
        drivesCubit: drivesCubit,
        profileCubit: profileCubit,
      );
    });

    tearDown(() async {
      await db.close();
    });

    blocTest<DriveCreateCubit, DriveCreateState>(
      'create public drive',
      build: () => driveCreateCubit,
      act: (bloc) async {
        bloc.form.value = {
          'name': validDriveName,
          'privacy': DrivePrivacy.public,
        };
        await bloc.submit();
      },
      expect: () => [
        DriveCreateInProgress(),
        DriveCreateSuccess(),
      ],
      verify: (_) {},
    );

    blocTest<DriveCreateCubit, DriveCreateState>(
      'create private drive',
      build: () => driveCreateCubit,
      act: (bloc) async {
        bloc.form.value = {
          'name': validDriveName,
          'privacy': DrivePrivacy.private,
        };
        await bloc.submit();
      },
      expect: () => [
        DriveCreateInProgress(),
        DriveCreateSuccess(),
      ],
      verify: (_) {},
    );

    blocTest<DriveCreateCubit, DriveCreateState>(
      'does nothing when submitted without valid form',
      build: () => driveCreateCubit,
      act: (bloc) => bloc.submit(),
      expect: () => [],
    );
  });
}
