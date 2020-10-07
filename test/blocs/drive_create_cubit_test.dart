import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drive/blocs/blocs.dart';
import 'package:drive/entities/entities.dart';
import 'package:drive/models/models.dart';
import 'package:drive/services/services.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../mocks.dart';
import '../utils.dart';

void main() {
  group('DriveCreateCubit', () {
    Database db;
    DrivesDao drivesDao;

    ArweaveService arweave;
    DrivesCubit drivesCubit;
    ProfileBloc profileBloc;
    DriveCreateCubit driveCreateCubit;

    const validDriveName = 'valid-drive-name';

    setUp(() {
      db = getTestDb();
      drivesDao = db.drivesDao;

      arweave = ArweaveService(Arweave());
      drivesCubit = MockDrivesCubit();
      profileBloc = MockProfileBloc();

      when(profileBloc.state).thenReturn(
        ProfileLoaded(
          password: '123',
          wallet: getTestWallet(),
          cipherKey: SecretKey.randomBytes(32),
        ),
      );

      driveCreateCubit = DriveCreateCubit(
        arweave: arweave,
        drivesDao: drivesDao,
        drivesCubit: drivesCubit,
        profileBloc: profileBloc,
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
        DriveCreateSuccessful(),
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
        DriveCreateSuccessful(),
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
