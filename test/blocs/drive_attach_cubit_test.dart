import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/utils.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';
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
    late DriveAttachCubit driveAttachCubit;

    const validPrivateDriveId = 'valid-private-drive-id';
    const validPrivateDriveKeyBase64 =
        'a6U1qYiJNNNfX6RqhCUGpwOfRN3ZdAiQl7LHywqIJTk';
    final validPrivateDriveKey = SecretKey(
      decodeBase64ToBytes(validPrivateDriveKeyBase64),
    );

    final keyBytes = Uint8List(32);
    fillBytesWithSecureRandom(keyBytes);
    final profileKey = SecretKey(keyBytes);

    const validDriveId = 'valid-drive-id';
    const validDriveName = 'valid-drive-name';
    const ownerAddress = 'owner-address';
    const validRootFolderId = 'valid-root-folder-id';
    const notFoundDriveId = 'not-found-drive-id';
    db = getTestDb();

    setUp(() {
      registerFallbackValue(SyncStateFake());
      registerFallbackValue(ProfileStateFake());
      registerFallbackValue(DrivesStateFake());

      driveDao = db.driveDao;

      arweave = MockArweaveService();
      syncBloc = MockSyncBloc();
      drivesBloc = MockDrivesCubit();
      when(() => arweave.getLatestDriveEntityWithId(validDriveId)).thenAnswer(
        (_) => Future.value(
          DriveEntity(
            id: validDriveId,
            name: validDriveName,
            privacy: DrivePrivacyTag.public,
            rootFolderId: validRootFolderId,
            authMode: DriveAuthModeTag.none,
          )..ownerAddress = ownerAddress,
        ),
      );

      when(() => arweave.getLatestDriveEntityWithId(
            validPrivateDriveId,
            driveKey: validPrivateDriveKey,
          )).thenAnswer(
        (_) => Future.value(
          DriveEntity(
            id: validPrivateDriveId,
            name: validDriveName,
            privacy: DrivePrivacyTag.private,
            rootFolderId: validRootFolderId,
            authMode: DriveAuthModeTag.password,
          )..ownerAddress = ownerAddress,
        ),
      );

      when(() => arweave.getLatestDriveEntityWithId(validPrivateDriveId))
          .thenAnswer((_) => Future.value(null));

      when(() => arweave.getLatestDriveEntityWithId(notFoundDriveId))
          .thenAnswer((_) => Future.value(null));
      when(() => arweave.getDrivePrivacyForId(validDriveId))
          .thenAnswer((_) => Future.value(DrivePrivacyTag.public));
      when(() => arweave.getDrivePrivacyForId(validPrivateDriveId))
          .thenAnswer((_) => Future.value(DrivePrivacyTag.private));

      when(() => syncBloc.startSync()).thenAnswer((_) => Future.value(null));

      when(() => syncBloc.waitCurrentSync())
          .thenAnswer((_) => Future.value(null));

      driveAttachCubit = DriveAttachCubit(
        arweave: arweave,
        driveDao: driveDao,
        syncBloc: syncBloc,
        drivesBloc: drivesBloc,
        profileKey: profileKey,
      );
    });

    blocTest<DriveAttachCubit, DriveAttachState>(
      'attach drive should start sync and should select the drive when given valid public drive details',
      build: () => driveAttachCubit,
      setUp: () {},
      act: (bloc) {
        bloc.driveIdController.text = validDriveId;
        bloc.driveNameController.text = validDriveName;

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
      'driveKey field is added to form when private drive id is used',
      build: () => driveAttachCubit,
      setUp: () {},
      act: (bloc) {
        bloc.driveIdController.text = validPrivateDriveId;
        bloc.drivePrivacyLoader();
      },
      expect: () => [
        DriveAttachPrivate(),
      ],
      wait: const Duration(milliseconds: 1000),
    );

    group('attach private drive while logged in', () {
      final invalidDriveKeyBase64 = base64Encode(Uint8List(32));
      final invalidDriveKey = SecretKey(
        decodeBase64ToBytes(invalidDriveKeyBase64),
      );

      setUp(() async {
        when(() => arweave.getLatestDriveEntityWithId(
              validPrivateDriveId,
              driveKey: invalidDriveKey,
            )).thenAnswer((_) => Future.value(null));
      });

      blocTest<DriveAttachCubit, DriveAttachState>(
        'emits invalid key state and the previous state when given invalid private drive details',
        build: () => driveAttachCubit,
        act: (bloc) async {
          await Future.microtask(() {
            bloc.driveIdController.text = validPrivateDriveId;
          });

          await Future.delayed(const Duration(milliseconds: 1000));

          bloc.driveKeyController.text = invalidDriveKeyBase64;

          await bloc.drivePrivacyLoader();

          await Future.delayed(const Duration(milliseconds: 1000));

          bloc.submit();
        },
        expect: () => [
          DriveAttachPrivate(),
          DriveAttachInvalidDriveKey(),
          DriveAttachPrivate()
        ],
        wait: const Duration(milliseconds: 1200),
        verify: (_) async {
          verifyZeroInteractions(syncBloc);
          verifyZeroInteractions(drivesBloc);
        },
      );

      blocTest<DriveAttachCubit, DriveAttachState>(
        'attach drive should start sync and should select the drive when given valid private drive details',
        build: () => DriveAttachCubit(
          arweave: arweave,
          driveDao: driveDao,
          syncBloc: syncBloc,
          drivesBloc: drivesBloc,
          profileKey: profileKey,
          initialDriveId: validPrivateDriveId,
          initialDriveName: validDriveName,
          initialDriveKey: validPrivateDriveKey,
        ),
        expect: () => [
          DriveAttachPrivate(),
          DriveAttachInProgress(),
          DriveAttachSuccess(),
        ],
        wait: const Duration(milliseconds: 1200),
        verify: (_) async {
          verify(() => syncBloc.startSync()).called(1);
          verify(() => drivesBloc.selectDrive(validPrivateDriveId)).called(1);
        },
      );
    });

    blocTest<DriveAttachCubit, DriveAttachState>(
      'does nothing when submitted without valid form',
      build: () => driveAttachCubit,
      act: (bloc) => bloc.submit(),
      expect: () => [DriveAttachDriveNotFound(), DriveAttachInitial()],
      verify: (_) {
        verifyZeroInteractions(arweave);
        verifyZeroInteractions(syncBloc);
        verifyZeroInteractions(drivesBloc);
      },
    );
  });
}
