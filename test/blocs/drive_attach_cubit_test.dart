import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/fakes.dart';
import '../test_utils/mocks.dart';

void main() {
  group('DriveAttachCubit', () {
    late ArweaveService arweave;
    late DriveDao driveDao;
    late SyncCubit syncBloc;
    late DrivesCubit drivesBloc;
    late ProfileCubit profileCubit;
    late DriveAttachCubit driveAttachCubit;

    const validDriveId = 'valid-drive-id';
    const validDriveName = 'valid-drive-name';

    const notFoundDriveId = 'not-found-drive-id';

    setUp(() {
      registerFallbackValue(SyncStatefake());
      registerFallbackValue(ProfileStatefake());
      registerFallbackValue(DrivesStatefake());

      arweave = MockArweaveService();
      driveDao = MockDriveDao();
      syncBloc = MockSyncBloc();
      drivesBloc = MockDrivesCubit();
      profileCubit = MockProfileCubit();
      when(() => arweave.getLatestDriveEntityWithId(validDriveId))
          .thenAnswer((_) => Future.value(DriveEntity()));

      when(() => arweave.getLatestDriveEntityWithId(notFoundDriveId))
          .thenAnswer((_) => Future.value(null));

      driveAttachCubit = DriveAttachCubit(
        arweave: arweave,
        driveDao: driveDao,
        syncBloc: syncBloc,
        drivesBloc: drivesBloc,
        profileCubit: profileCubit,
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
      expect: () => [
        DriveAttachInProgress(),
        DriveAttachSuccess(),
      ],
      verify: (_) {
        verify(() => syncBloc.startSync()).called(1);
        verify(() => drivesBloc.selectDrive(validDriveId)).called(1);
      },
    );

    blocTest<DriveAttachCubit, DriveAttachState>(
      'set form "${AppValidationMessage.driveNotFound}" error when no valid drive could be found',
      build: () => driveAttachCubit,
      act: (bloc) {
        bloc.form.value = {
          'driveId': notFoundDriveId,
          'name': 'fake',
        };
        bloc.submit();
      },
      expect: () => [
        DriveAttachInProgress(),
        DriveAttachInitial(),
      ],
    );

    blocTest<DriveAttachCubit, DriveAttachState>(
      'does nothing when submitted without valid form',
      build: () => driveAttachCubit,
      act: (bloc) => bloc.submit(),
      expect: () => [],
      verify: (_) {
        verifyZeroInteractions(arweave);
        verifyZeroInteractions(driveDao);
        verifyZeroInteractions(syncBloc);
        verifyZeroInteractions(drivesBloc);
      },
    );
  });
}
