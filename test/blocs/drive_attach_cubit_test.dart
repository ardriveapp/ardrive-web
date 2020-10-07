import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drive/blocs/blocs.dart';
import 'package:drive/entities/entities.dart';
import 'package:drive/models/models.dart';
import 'package:drive/services/services.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group('DriveAttachCubit', () {
    ArweaveService arweave;
    DrivesDao drivesDao;
    ProfileBloc profileBloc;
    SyncBloc syncBloc;
    DrivesCubit drivesBloc;
    DriveAttachCubit driveAttachCubit;

    const validDriveId = 'valid-drive-id';
    const validDriveName = 'valid-drive-name';

    const notFoundDriveId = 'not-found-drive-id';

    setUp(() {
      arweave = MockArweaveService();
      drivesDao = MockDrivesDao();
      syncBloc = MockSyncBloc();
      drivesBloc = MockDrivesCubit();
      profileBloc = MockProfileBloc();

      when(arweave.tryGetFirstDriveEntityWithId(validDriveId))
          .thenAnswer((_) => Future.value(DriveEntity()));

      when(arweave.tryGetFirstDriveEntityWithId(notFoundDriveId))
          .thenAnswer((_) => Future.value(null));

      when(profileBloc.state)
          .thenReturn(ProfileLoaded(cipherKey: SecretKey.randomBytes(256)));

      driveAttachCubit = DriveAttachCubit(
        arweave: arweave,
        drivesDao: drivesDao,
        syncBloc: syncBloc,
        drivesBloc: drivesBloc,
        profileBloc: profileBloc,
      );
    });

    blocTest<DriveAttachCubit, DriveAttachState>(
      'attach drive and trigger actions when given valid details',
      build: () => driveAttachCubit,
      act: (bloc) {
        bloc.form.value = {
          'driveId': validDriveId,
          'name': validDriveName,
        };
        bloc.submit();
      },
      expect: [
        DriveAttachInProgress(),
        DriveAttachSuccess(),
      ],
      verify: (_) {
        verify(syncBloc.add(SyncWithNetwork()));
        verify(drivesBloc.selectDrive(validDriveId));
      },
    );

    blocTest<DriveAttachCubit, DriveAttachState>(
      'set form "drive-not-found error" when no valid drive could be found',
      build: () => driveAttachCubit,
      act: (bloc) {
        bloc.form.value = {
          'driveId': notFoundDriveId,
          'name': 'fake',
        };
        bloc.submit();
      },
      expect: [
        DriveAttachInProgress(),
        DriveAttachInitial(),
      ],
    );

    blocTest<DriveAttachCubit, DriveAttachState>(
      'does nothing when submitted without valid form',
      build: () => driveAttachCubit,
      act: (bloc) => bloc.submit(),
      expect: [],
      verify: (_) {
        verifyZeroInteractions(arweave);
        verifyZeroInteractions(drivesDao);
        verifyZeroInteractions(syncBloc);
        verifyZeroInteractions(drivesBloc);
        verifyZeroInteractions(profileBloc);
      },
    );
  });
}
