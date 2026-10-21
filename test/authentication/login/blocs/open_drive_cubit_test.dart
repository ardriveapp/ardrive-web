import 'package:ardrive/authentication/login/blocs/open_drive_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../test_utils/mocks.dart';

/// The visitor's path through "Open a drive": the chain is asked what the
/// pasted text names, a private drive waits for its key, and Open writes the
/// row with no profile key and hands the drive to the router.
void main() {
  const publicDriveId = 'a2b7ba0a-3b2a-4c1b-8a2f-6d1a0b3c4d5e';
  const privateDriveId = 'b3c8cb1b-4c3b-5d2c-9b3f-7e2b1c4d5e6f';
  const missingDriveId = 'c4d9dc2c-5d4c-6e3d-ac4f-8f3c2d5e6f70';
  const brokenDriveId = 'd5eaed3d-6e5d-7f4e-bd5f-9f4d3e6f7a81';
  const rootFolderId = 'e6fbfe4e-7f6e-8a5f-ce6f-af5e4f7a8b92';
  const owner = 'test-owner';

  // 32 zero bytes, base64url.
  const rightKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
  // 32 one-bytes, base64url: well formed, and not the drive's key.
  const wrongKey = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE';

  late MockArweaveService arweave;
  late MockDriveDao driveDao;

  DriveEntity publicDrive() => DriveEntity(
        id: publicDriveId,
        name: 'Family Photos',
        privacy: DrivePrivacyTag.public,
        rootFolderId: rootFolderId,
        authMode: DriveAuthModeTag.none,
      )..ownerAddress = owner;

  DriveEntity privateDrive() => DriveEntity(
        id: privateDriveId,
        name: 'Tax Returns',
        privacy: DrivePrivacyTag.private,
        rootFolderId: rootFolderId,
        authMode: DriveAuthModeTag.password,
      )..ownerAddress = owner;

  DrivePrivacyResult privacy(String tag) => DrivePrivacyResult(
        privacy: tag,
        ownerAddress: owner,
        driveTx: MockTransactionCommonMixin(),
      );

  /// Whether [key] decodes to the 32 zero bytes the right key is.
  Future<bool> isRightKey(SecretKey key) async =>
      (await key.extractBytes()).every((b) => b == 0);

  setUpAll(() {
    registerFallbackValue(DriveEntity());
    registerFallbackValue(SecretKey(List.filled(32, 0)));
  });

  setUp(() {
    arweave = MockArweaveService();
    driveDao = MockDriveDao();

    when(() => arweave.getDrivePrivacyForId(publicDriveId))
        .thenAnswer((_) async => privacy(DrivePrivacyTag.public));
    when(() => arweave.getDrivePrivacyForId(privateDriveId))
        .thenAnswer((_) async => privacy(DrivePrivacyTag.private));
    when(() => arweave.getDrivePrivacyForId(missingDriveId))
        .thenAnswer((_) async => null);
    when(() => arweave.getDrivePrivacyForId(brokenDriveId))
        .thenThrow(Exception('gateway unreachable'));

    when(() => arweave.getLatestDriveEntityWithId(
          publicDriveId,
          driveOwner: owner,
        )).thenAnswer((_) async => publicDrive());

    // The private drive decrypts with the right key and with nothing else.
    when(() => arweave.getLatestDriveEntityWithId(
          privateDriveId,
          driveKey: any(named: 'driveKey'),
        )).thenAnswer((invocation) async {
      final key = invocation.namedArguments[#driveKey] as SecretKey?;
      return key != null && await isRightKey(key) ? privateDrive() : null;
    });

    when(() => driveDao.writeDriveEntity(
          name: any(named: 'name'),
          entity: any(named: 'entity'),
          driveKey: any(named: 'driveKey'),
          profileKey: any(named: 'profileKey'),
        )).thenAnswer((_) async {});
  });

  OpenDriveCubit build() => OpenDriveCubit(
        arweave: arweave,
        driveDao: driveDao,
        lookupDelay: Duration.zero,
      );

  group('looking up', () {
    blocTest<OpenDriveCubit, OpenDriveState>(
      'a public drive id finds the drive and is ready to open',
      build: build,
      act: (cubit) => cubit.inputChanged(publicDriveId),
      wait: const Duration(milliseconds: 10),
      expect: () => [
        const OpenDriveLookingUp(),
        const OpenDrivePublic(driveId: publicDriveId, name: 'Family Photos'),
      ],
      verify: (cubit) => expect(cubit.state.canOpen, isTrue),
    );

    blocTest<OpenDriveCubit, OpenDriveState>(
      'a link with a folder finds the same drive',
      build: build,
      act: (cubit) => cubit.inputChanged(
        'https://app.ardrive.io/#/drives/$publicDriveId/folders/$rootFolderId',
      ),
      wait: const Duration(milliseconds: 10),
      expect: () => [
        const OpenDriveLookingUp(),
        const OpenDrivePublic(driveId: publicDriveId, name: 'Family Photos'),
      ],
    );

    blocTest<OpenDriveCubit, OpenDriveState>(
      'a private drive id waits for a key and cannot open yet',
      build: build,
      act: (cubit) => cubit.inputChanged(privateDriveId),
      wait: const Duration(milliseconds: 10),
      expect: () => [
        const OpenDriveLookingUp(),
        const OpenDrivePrivate(driveId: privateDriveId),
      ],
      verify: (cubit) => expect(cubit.state.canOpen, isFalse),
    );

    blocTest<OpenDriveCubit, OpenDriveState>(
      'an unknown id is not found',
      build: build,
      act: (cubit) => cubit.inputChanged(missingDriveId),
      wait: const Duration(milliseconds: 10),
      expect: () => [
        const OpenDriveLookingUp(),
        const OpenDriveNotFound(),
      ],
    );

    blocTest<OpenDriveCubit, OpenDriveState>(
      'a gateway that cannot be reached is a network error, not a crash',
      build: build,
      act: (cubit) => cubit.inputChanged(brokenDriveId),
      wait: const Duration(milliseconds: 10),
      expect: () => [
        const OpenDriveLookingUp(),
        const OpenDriveNetworkError(),
      ],
    );

    blocTest<OpenDriveCubit, OpenDriveState>(
      'text that is not a link or an id says nothing until the field is left',
      build: build,
      act: (cubit) async {
        cubit.inputChanged('hello there');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await cubit.inputBlurred('hello there');
      },
      expect: () => [
        const OpenDriveUnrecognisedInput(),
      ],
    );

    blocTest<OpenDriveCubit, OpenDriveState>(
      'a file link is handed on as a link, not looked up as a drive',
      build: build,
      act: (cubit) => cubit.inputChanged(
        'https://app.ardrive.io/#/file/$publicDriveId/view',
      ),
      wait: const Duration(milliseconds: 10),
      verify: (cubit) {
        final state = cubit.state;
        expect(state, isA<OpenDriveOtherLink>());
        expect((state as OpenDriveOtherLink).isFile, isTrue);
        expect(state.canOpen, isTrue);
        verifyNever(() => arweave.getDrivePrivacyForId(any()));
      },
    );

    blocTest<OpenDriveCubit, OpenDriveState>(
      'clearing the field goes back to the start',
      build: build,
      act: (cubit) async {
        cubit.inputChanged(publicDriveId);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        cubit.inputChanged('');
      },
      expect: () => [
        const OpenDriveLookingUp(),
        const OpenDrivePublic(driveId: publicDriveId, name: 'Family Photos'),
        const OpenDriveInitial(),
      ],
    );
  });

  group('a private drive', () {
    blocTest<OpenDriveCubit, OpenDriveState>(
      'accepts the right key and learns its name',
      build: build,
      act: (cubit) async {
        cubit.inputChanged(privateDriveId);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        cubit.keyChanged(rightKey);
      },
      wait: const Duration(milliseconds: 10),
      expect: () => [
        const OpenDriveLookingUp(),
        const OpenDrivePrivate(driveId: privateDriveId),
        const OpenDrivePrivate(driveId: privateDriveId, validating: true),
        const OpenDrivePrivate(driveId: privateDriveId, name: 'Tax Returns'),
      ],
      verify: (cubit) => expect(cubit.state.canOpen, isTrue),
    );

    blocTest<OpenDriveCubit, OpenDriveState>(
      'rejects a key that does not open it',
      build: build,
      act: (cubit) async {
        cubit.inputChanged(privateDriveId);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        cubit.keyChanged(wrongKey);
      },
      wait: const Duration(milliseconds: 10),
      expect: () => [
        const OpenDriveLookingUp(),
        const OpenDrivePrivate(driveId: privateDriveId),
        const OpenDrivePrivate(driveId: privateDriveId, validating: true),
        const OpenDrivePrivate(driveId: privateDriveId, keyRejected: true),
      ],
      verify: (cubit) => expect(cubit.state.canOpen, isFalse),
    );

    blocTest<OpenDriveCubit, OpenDriveState>(
      'rejects text that is not a key at all',
      build: build,
      act: (cubit) async {
        cubit.inputChanged(privateDriveId);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        cubit.keyChanged('not a key');
      },
      wait: const Duration(milliseconds: 10),
      expect: () => [
        const OpenDriveLookingUp(),
        const OpenDrivePrivate(driveId: privateDriveId),
        const OpenDrivePrivate(driveId: privateDriveId, keyRejected: true),
      ],
    );

    blocTest<OpenDriveCubit, OpenDriveState>(
      'opens in one step from a link that carries the key',
      build: build,
      act: (cubit) => cubit.inputChanged(
        'https://app.ardrive.io/#/drives/$privateDriveId?driveKey=$rightKey',
      ),
      wait: const Duration(milliseconds: 10),
      expect: () => [
        const OpenDriveLookingUp(),
        const OpenDrivePrivate(
          driveId: privateDriveId,
          prefilledKey: rightKey,
          validating: true,
        ),
        const OpenDrivePrivate(
          driveId: privateDriveId,
          prefilledKey: rightKey,
          name: 'Tax Returns',
        ),
      ],
      verify: (cubit) => expect(cubit.state.canOpen, isTrue),
    );
  });

  group('opening', () {
    blocTest<OpenDriveCubit, OpenDriveState>(
      'writes a public drive with no profile key and hands it over',
      build: build,
      act: (cubit) async {
        cubit.inputChanged(publicDriveId);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await cubit.open();
      },
      expect: () => [
        const OpenDriveLookingUp(),
        const OpenDrivePublic(driveId: publicDriveId, name: 'Family Photos'),
        const OpenDriveOpening(),
        const OpenDriveOpened(driveId: publicDriveId),
      ],
      verify: (_) {
        final call = verify(() => driveDao.writeDriveEntity(
              name: captureAny(named: 'name'),
              entity: captureAny(named: 'entity'),
              driveKey: captureAny(named: 'driveKey'),
              profileKey: captureAny(named: 'profileKey'),
            ))
          ..called(1);

        expect(call.captured[0], 'Family Photos');
        expect((call.captured[1] as DriveEntity).id, publicDriveId);
        expect(call.captured[2], isNull);
        expect(call.captured[3], isNull);
      },
    );

    blocTest<OpenDriveCubit, OpenDriveState>(
      'writes a private drive with its key, in memory only, and hands the '
      'key over for the address bar',
      build: build,
      act: (cubit) async {
        cubit.inputChanged(privateDriveId);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        cubit.keyChanged(rightKey);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await cubit.open();
      },
      verify: (cubit) async {
        final state = cubit.state;
        expect(state, isA<OpenDriveOpened>());
        expect((state as OpenDriveOpened).driveId, privateDriveId);
        expect(state.rawDriveKey, rightKey);
        expect(state.driveKey, isNotNull);

        final call = verify(() => driveDao.writeDriveEntity(
              name: any(named: 'name'),
              entity: any(named: 'entity'),
              driveKey: captureAny(named: 'driveKey'),
              profileKey: captureAny(named: 'profileKey'),
            ))
          ..called(1);

        final key = call.captured[0] as DriveKey;
        expect(await isRightKey(key.key), isTrue);
        expect(call.captured[1], isNull);
      },
    );

    blocTest<OpenDriveCubit, OpenDriveState>(
      'does nothing before a drive is ready',
      build: build,
      act: (cubit) => cubit.open(),
      expect: () => <OpenDriveState>[],
      verify: (_) => verifyNever(() => driveDao.writeDriveEntity(
            name: any(named: 'name'),
            entity: any(named: 'entity'),
            driveKey: any(named: 'driveKey'),
            profileKey: any(named: 'profileKey'),
          )),
    );

    blocTest<OpenDriveCubit, OpenDriveState>(
      'reports a write that failed rather than closing on nothing',
      build: build,
      setUp: () {
        when(() => driveDao.writeDriveEntity(
              name: any(named: 'name'),
              entity: any(named: 'entity'),
              driveKey: any(named: 'driveKey'),
              profileKey: any(named: 'profileKey'),
            )).thenThrow(Exception('disk full'));
      },
      act: (cubit) async {
        cubit.inputChanged(publicDriveId);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await cubit.open();
      },
      expect: () => [
        const OpenDriveLookingUp(),
        const OpenDrivePublic(driveId: publicDriveId, name: 'Family Photos'),
        const OpenDriveOpening(),
        const OpenDriveFailure(),
      ],
    );
  });
}
