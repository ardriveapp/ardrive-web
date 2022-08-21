import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
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

    setUp(() {
      registerFallbackValue(SyncStateFake());
      registerFallbackValue(ProfileStateFake());
      registerFallbackValue(DrivesStateFake());

      db = getTestDb();
      driveDao = db.driveDao;

      arweave = MockArweaveService();
      syncBloc = MockSyncBloc();
      drivesBloc = MockDrivesCubit();
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

      when(() => arweave.getLatestDriveEntityWithId(
            validPrivateDriveId,
            validPrivateDriveKey,
          )).thenAnswer(
        (_) => Future.value(
          DriveEntity(
            id: validPrivateDriveId,
            name: validDriveName,
            privacy: DrivePrivacy.private,
            rootFolderId: validRootFolderId,
            authMode: DriveAuthMode.password,
          )..ownerAddress = ownerAddress,
        ),
      );

      when(() => arweave.getLatestDriveEntityWithId(validPrivateDriveId))
          .thenAnswer((_) => Future.value(null));

      when(() => arweave.getLatestDriveEntityWithId(notFoundDriveId))
          .thenAnswer((_) => Future.value(null));
      when(() => arweave.getDrivePrivacyForId(validDriveId))
          .thenAnswer((_) => Future.value(DrivePrivacy.public));
      when(() => arweave.getDrivePrivacyForId(validPrivateDriveId))
          .thenAnswer((_) => Future.value(DrivePrivacy.private));

      when(() => syncBloc.startSync()).thenAnswer((_) => Future.value(null));

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
      'driveKey field is added to form when private drive id is used',
      build: () => driveAttachCubit,
      setUp: () {},
      act: (bloc) {
        bloc.form.value = {
          'driveId': validPrivateDriveId,
        };
        bloc.form.updateValueAndValidity();
      },
      wait: const Duration(milliseconds: 1000),
      verify: (bloc) {
        expect(bloc.form.contains('driveKey'), isTrue);
      },
    );

    group('attach private drive while logged in', () {
      final invalidDriveKeyBase64 = base64Encode(Uint8List(32));
      final invalidDriveKey = SecretKey(
        decodeBase64ToBytes(invalidDriveKeyBase64),
      );

      setUp(() async {
        when(() => arweave.getLatestDriveEntityWithId(
              validPrivateDriveId,
              invalidDriveKey,
            )).thenAnswer((_) => Future.value(null));
      });

      blocTest<DriveAttachCubit, DriveAttachState>(
        'does nothing when submitted without valid drive key',
        build: () => driveAttachCubit,
        act: (bloc) async {
          await Future.microtask(() {
            bloc.form.control('driveId').updateValue(validPrivateDriveId);
          });
          await Future.delayed(const Duration(milliseconds: 1000));
          bloc.form.control('driveKey').updateValue(invalidDriveKeyBase64);
          await Future.delayed(const Duration(milliseconds: 1000));
          bloc.submit();
        },
        expect: () => [
          DriveAttachPrivate(),
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
          DriveAttachInProgress(),
          DriveAttachSuccess(),
          // This state is here after DriveAttachSuccess due to debounced validation after drive attaches
          DriveAttachPrivate(),
        ],
        wait: const Duration(milliseconds: 1200),
        verify: (_) async {
          verify(() => syncBloc.startSync()).called(1);
          verify(() => drivesBloc.selectDrive(validPrivateDriveId)).called(1);
        },
      );
    });

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
