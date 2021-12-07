import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moor/moor.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:test/test.dart';

import '../utils/fake_data.dart';
import '../utils/fakes.dart';
import '../utils/utils.dart';

void main() {
  group('DriveCreateCubit', () {
    late Database db;
    late DriveDao driveDao;

    late ArweaveService arweave;
    late DrivesCubit drivesCubit;
    late ProfileCubit profileCubit;
    late DriveCreateCubit driveCreateCubit;

    const validDriveName = 'valid-drive-name';
    const testGatewayURL = 'https://arweave.net';

    setUp(() async {
      registerFallbackValue(DrivesStatefake());
      registerFallbackValue(ProfileStatefake());

      db = getTestDb();
      driveDao = db.driveDao;

      arweave = ArweaveService(Arweave(gatewayUrl: Uri.parse(testGatewayURL)));
      drivesCubit = MockDrivesCubit();
      profileCubit = MockProfileCubit();

      PackageInfo.setMockInitialValues(
        appName: appName,
        packageName: packageName,
        version: version,
        buildNumber: buildNumber,
        buildSignature: buildSignature,
      );

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
          walletBalance: BigInt.from(20000000),
          cipherKey: SecretKey(keyBytes),
        ),
      );
      when(() => profileCubit.logoutIfWalletMismatch())
          .thenAnswer((_) => Future.value(false));

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