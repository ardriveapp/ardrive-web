import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../utils/utils.dart';

void main() {
  group('DriveCreateCubit', () {
    Database db;
    DriveDao driveDao;

    ArweaveService arweave;
    DrivesCubit drivesCubit;
    ProfileCubit profileCubit;
    DriveCreateCubit driveCreateCubit;

    const validDriveName = 'valid-drive-name';

    setUp(() {
      db = getTestDb();
      driveDao = db.driveDao;

      arweave = ArweaveService(Arweave());
      drivesCubit = MockDrivesCubit();
      profileCubit = MockProfileCubit();

      when(profileCubit.state).thenReturn(
        ProfileLoggedIn(
          password: '123',
          wallet: getTestWallet(),
          cipherKey: SecretKey.(32),
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
      expect: [
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
      expect: [
        DriveCreateInProgress(),
        DriveCreateSuccess(),
      ],
      verify: (_) {},
    );

    blocTest<DriveCreateCubit, DriveCreateState>(
      'does nothing when submitted without valid form',
      build: () => driveCreateCubit,
      act: (bloc) => bloc.submit(),
      expect: [],
    );
  });
}
