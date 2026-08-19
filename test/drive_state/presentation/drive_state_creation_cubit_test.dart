import 'dart:typed_data';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_entity.dart';
import 'package:ardrive/drive_state/domain/drive_state_sync_skip_status.dart';
import 'package:ardrive/drive_state/domain/drive_state_uploader.dart';
import 'package:ardrive/drive_state/presentation/drive_state_creation_cubit/drive_state_creation_cubit.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

/// The cubit's contract: preparing never publishes, and publishing happens
/// only from the state a user was shown.
///
/// The upload collaborator is a mock throughout, and every path except the one
/// that follows a confirm asserts it was never touched — `DECISIONS.md` D8
/// makes "nothing is uploaded by any agent" a rail, and a test that quietly
/// spent money would be the thing that broke it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const driveId = 'drive-id';
  const rootFolderId = 'root-folder-id';
  const nestedFolderId = 'nested-folder-id';
  const lastBlockHeight = 1814228;

  final profileKey = SecretKey(List.filled(32, 3));
  final driveKey = SecretKey(List.filled(32, 7));

  late Database db;
  late DriveDao driveDao;
  late ProfileCubit profileCubit;
  late _MockUploader uploader;
  late String ownerAddress;

  setUpAll(() async {
    ownerAddress = await getTestWallet().getAddress();
    registerFallbackValue(_anyArtifact());
  });

  /// A private drive, owned by the test wallet, with its key wrapped in the
  /// profile key exactly as `DriveDao` writes it — so `getDriveKey` reads it
  /// back out.
  Future<void> insertDrive({String privacy = DrivePrivacyTag.private}) async {
    final encryption = await AesGcm.with256bits().encrypt(
      await driveKey.extractBytes(),
      secretKey: profileKey,
    );

    await (db.update(db.drives)..where((d) => d.id.equals(driveId))).write(
      DrivesCompanion(
        privacy: Value(privacy),
        ownerAddress: Value(ownerAddress),
        lastBlockHeight: const Value(lastBlockHeight),
        encryptedKey: privacy == DrivePrivacyTag.private
            ? Value(encryption.concatenation(nonce: false))
            : const Value(null),
        keyEncryptionIv: privacy == DrivePrivacyTag.private
            ? Value(Uint8List.fromList(encryption.nonce))
            : const Value(null),
      ),
    );
  }

  setUp(() async {
    db = getTestDb();
    driveDao = db.driveDao;
    uploader = _MockUploader();
    profileCubit = MockProfileCubit();

    when(() => profileCubit.state).thenReturn(
      ProfileLoggedIn(
        user: User(
          password: 'password',
          wallet: getTestWallet(),
          walletAddress: ownerAddress,
          walletBalance: BigInt.zero,
          cipherKey: profileKey,
          profileType: ProfileType.json,
          errorFetchingIOTokens: false,
        ),
        useTurbo: false,
      ),
    );

    await addTestFilesToDb(
      db,
      driveId: driveId,
      rootFolderId: rootFolderId,
      nestedFolderId: nestedFolderId,
      emptyNestedFolderCount: 1,
      emptyNestedFolderIdPrefix: 'empty-nested-folder-id',
      rootFolderFileCount: 2,
      nestedFolderFileCount: 1,
    );

    await insertDrive();
  });

  tearDown(() => db.close());

  DriveStateCreationCubit cubitWith({
    DriveStateSyncSkipStatus skipStatus =
        const DriveStateSyncSkipStatus.clean(),
  }) =>
      DriveStateCreationCubit(
        driveId: driveId,
        service: DriveStateCreationService(
          driveDao: driveDao,
          skipSource: _FixedSkipSource(skipStatus),
        ),
        uploader: uploader,
        profileCubit: profileCubit,
        driveDao: driveDao,
      );

  group('prepare', () {
    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'lands on a ready artifact without publishing anything',
      build: cubitWith,
      act: (cubit) => cubit.prepare(),
      expect: () => [
        isA<DriveStateCreationPreparing>(),
        isA<DriveStateCreationReady>()
            .having((s) => s.artifact.driveId, 'driveId', driveId)
            .having((s) => s.artifact.blockEnd, 'blockEnd', lastBlockHeight)
            .having((s) => s.artifact.sizeInBytes, 'size', greaterThan(0)),
      ],
      verify: (_) => verifyNever(() => uploader.publish(any())),
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'refuses a drive whose last sync skipped entities, and seals nothing',
      build: () => cubitWith(
        skipStatus: const DriveStateSyncSkipStatus.skipped(
          skippedEntityCount: 2,
          reason: 'The last sync of this drive could not read 2 items.',
        ),
      ),
      act: (cubit) => cubit.prepare(),
      expect: () => [
        isA<DriveStateCreationPreparing>(),
        isA<DriveStateCreationRefused>()
            .having(
              (s) => s.refusal,
              'refusal',
              DriveStateCreationRefusal.syncSkippedEntities,
            )
            .having((s) => s.isSyncGap, 'isSyncGap', isTrue)
            .having((s) => s.reason, 'reason', contains('2 items')),
      ],
      verify: (_) => verifyNever(() => uploader.publish(any())),
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'refuses when the skip state cannot be established',
      build: () => cubitWith(
        skipStatus: const DriveStateSyncSkipStatus.unknown('No sync yet.'),
      ),
      act: (cubit) => cubit.prepare(),
      expect: () => [
        isA<DriveStateCreationPreparing>(),
        isA<DriveStateCreationRefused>()
            .having(
              (s) => s.refusal,
              'refusal',
              DriveStateCreationRefusal.skipStateUnknown,
            )
            .having((s) => s.isSyncGap, 'isSyncGap', isTrue),
      ],
      verify: (_) => verifyNever(() => uploader.publish(any())),
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'refuses a public drive, which has no drive key to seal under',
      build: cubitWith,
      setUp: () => insertDrive(privacy: DrivePrivacyTag.public),
      act: (cubit) => cubit.prepare(),
      expect: () => [
        isA<DriveStateCreationPreparing>(),
        isA<DriveStateCreationRefused>().having(
          (s) => s.refusal,
          'refusal',
          DriveStateCreationRefusal.publicDriveUnsupported,
        ),
      ],
      verify: (_) => verifyNever(() => uploader.publish(any())),
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'refuses when nobody is logged in',
      build: cubitWith,
      setUp: () => when(() => profileCubit.state).thenReturn(ProfileLoggingOut()),
      act: (cubit) => cubit.prepare(),
      expect: () => [
        isA<DriveStateCreationPreparing>(),
        isA<DriveStateCreationRefused>(),
      ],
      verify: (_) => verifyNever(() => uploader.publish(any())),
    );
  });

  group('publish', () {
    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'is ignored unless an artifact was prepared and shown',
      build: cubitWith,
      act: (cubit) => cubit.publish(),
      expect: () => <DriveStateCreationState>[],
      verify: (_) => verifyNever(() => uploader.publish(any())),
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'hands the prepared artifact to the uploader, once, on confirmation',
      build: cubitWith,
      setUp: () => when(() => uploader.publish(any())).thenAnswer(
        (_) async => const DriveStateUploadResult.published('tx-id'),
      ),
      act: (cubit) async {
        await cubit.prepare();
        await cubit.publish();
      },
      skip: 2,
      expect: () => [
        isA<DriveStateCreationPublishing>(),
        isA<DriveStateCreationPublished>()
            .having((s) => s.txId, 'txId', 'tx-id'),
      ],
      verify: (_) => verify(() => uploader.publish(any())).called(1),
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'reports the seam refusing, as this build always does',
      build: cubitWith,
      setUp: () => when(() => uploader.publish(any())).thenAnswer(
        (_) async => const DriveStateUploadResult.failed('not enabled'),
      ),
      act: (cubit) async {
        await cubit.prepare();
        await cubit.publish();
      },
      skip: 2,
      expect: () => [
        isA<DriveStateCreationPublishing>(),
        isA<DriveStateCreationFailure>()
            .having((s) => s.message, 'message', 'not enabled'),
      ],
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'survives an uploader that throws',
      build: cubitWith,
      setUp: () => when(() => uploader.publish(any())).thenThrow(
        Exception('the network went away'),
      ),
      act: (cubit) async {
        await cubit.prepare();
        await cubit.publish();
      },
      skip: 2,
      expect: () => [
        isA<DriveStateCreationPublishing>(),
        isA<DriveStateCreationFailure>()
            .having((s) => s.message, 'message', contains('Nothing was spent')),
      ],
    );
  });

  group('the shipped uploader', () {
    test('publishes nothing, and says so', () async {
      final result = await const UnwiredDriveStateUploader()
          .publish(_anyArtifact());

      expect(result.isPublished, isFalse);
      expect(result.reason, contains('Nothing was uploaded'));
    });
  });
}

class _MockUploader extends Mock implements DriveStateUploader {}

class _FixedSkipSource implements DriveStateSyncSkipSource {
  final DriveStateSyncSkipStatus _status;

  const _FixedSkipSource(this._status);

  @override
  DriveStateSyncSkipStatus statusFor(String driveId) => _status;
}

PreparedDriveStateArtifact _anyArtifact() => PreparedDriveStateArtifact(
      entity: DriveStateEntity(),
      driveId: 'drive-id',
      driveName: 'drive',
      entityCount: 1,
      sizeInBytes: 1,
    );
