import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/fakes.dart';
import '../test_utils/utils.dart';

void main() {
  group('DriveAttachCubit', () {
    late Database db;
    late ArweaveService arweave;
    late DriveDao driveDao;
    late SyncCubit syncBloc;
    late DrivesCubit drivesBloc;
    late ProfileCubit profileCubit;
    late DriveAttachCubit driveAttachCubit;

    const validDriveId = 'valid-drive-id';
    const validDriveName = 'valid-drive-name';
    const ownerAddress = 'owner-address';
    const validRootFolderId = 'valid-root-folder-id';
    const notFoundDriveId = 'not-found-drive-id';

    setUp(() {
      registerFallbackValue(SyncStatefake());
      registerFallbackValue(ProfileStatefake());
      registerFallbackValue(DrivesStatefake());

      db = getTestDb();
      driveDao = db.driveDao;

      arweave = MockArweaveService();
      syncBloc = MockSyncBloc();
      drivesBloc = MockDrivesCubit();
      profileCubit = MockProfileCubit();
      when(() => arweave.getLatestDriveEntityWithId(validDriveId)).thenAnswer(
        (_) => Future.value(
          DriveEntity(
            id: validDriveId,
            name: validDriveName,
            privacy: DrivePrivacy.public,
            rootFolderId: validRootFolderId,
            authMode: DriveAuthMode.none,
          )..ownerAddress = ownerAddress,
        ),
      );

      when(() => arweave.getLatestDriveEntityWithId(notFoundDriveId))
          .thenAnswer((_) => Future.value(null));
      when(() => arweave.getDrivePrivacyForId(validDriveId))
          .thenAnswer((_) => Future.value(DrivePrivacy.public));
      when(() => syncBloc.startSync()).thenAnswer((_) => Future.value(null));
      profileCubit.emit(ProfileLoggingOut());
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
      setUp: () {},
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
      'set form "${AppValidationMessage.driveAttachDriveNotFound}" error when no valid drive could be found',
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
        verifyZeroInteractions(syncBloc);
        verifyZeroInteractions(drivesBloc);
      },
    );
  });
}
