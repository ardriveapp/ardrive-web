import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_entity.dart';
import 'package:ardrive/drive_state/domain/drive_state_publish_cost.dart';
import 'package:ardrive/drive_state/domain/drive_state_sync_skip_status.dart';
import 'package:ardrive/drive_state/domain/drive_state_uploader.dart';
import 'package:ardrive/drive_state/presentation/drive_state_creation_cubit/drive_state_creation_cubit.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

/// The cubit's contract: preparing never publishes, publishing happens only
/// from the state a user was shown, and nothing publishes that the user cannot
/// pay for.
///
/// The upload collaborator is a mock throughout, and every path except the one
/// that follows a confirm asserts it was never touched — `DECISIONS.md` D8
/// makes "nothing is uploaded by any agent" a rail, and a test that quietly
/// spent money would be the thing that broke it. The cost estimator is a mock
/// too: pricing an artifact means asking a gateway and a payment service, and
/// neither belongs in a test.
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
  late _MockCostEstimator costEstimator;
  late String ownerAddress;

  setUpAll(() async {
    ownerAddress = await getTestWallet().getAddress();
    registerFallbackValue(_anyArtifact());
    registerFallbackValue(getTestWallet());
    registerFallbackValue(BigInt.zero);
    registerFallbackValue(UploadMethod.ar);
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
    costEstimator = _MockCostEstimator();
    profileCubit = MockProfileCubit();

    when(() => costEstimator.estimate(
          sizeInBytes: any(named: 'sizeInBytes'),
          wallet: any(named: 'wallet'),
          walletBalance: any(named: 'walletBalance'),
        )).thenAnswer((_) async => _cost());

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
        costEstimator: costEstimator,
        profileCubit: profileCubit,
        driveDao: driveDao,
        turboBalanceRefreshDelay: Duration.zero,
        costEstimateTimeout: const Duration(milliseconds: 50),
      );

  group('a cost estimate that never returns', () {
    // None of the calls inside `estimate` carries a deadline, and several are
    // guarded only against *errors* — a try/catch does nothing for a future
    // that never completes. Before the deadline, that left the modal showing
    // "Preparing an artifact" for ever, with no log and no way for the user to
    // tell a slow answer from no answer. It cost an afternoon of guessing.
    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'is given up on, and says so, rather than spinning for ever',
      setUp: () {
        when(() => costEstimator.estimate(
              sizeInBytes: any(named: 'sizeInBytes'),
              wallet: any(named: 'wallet'),
              walletBalance: any(named: 'walletBalance'),
              // Never completes. Not an error: the case a catch cannot see.
            )).thenAnswer((_) => Completer<DriveStatePublishCost>().future);
      },
      build: cubitWith,
      act: (cubit) => cubit.prepare(),
      verify: (cubit) {
        final state = cubit.state as DriveStateCreationFailure;
        expect(state.message, contains('longer than'));
        expect(state.message, contains('nothing was spent'),
            reason: 'the user must be told no money moved');
      },
    );
  });

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
            .having((s) => s.artifact.sizeInBytes, 'size', greaterThan(0))
            .having((s) => s.canPublish, 'canPublish', isTrue),
      ],
      verify: (_) => verifyNever(
          () => uploader.publish(any(), method: any(named: 'method'))),
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
      verify: (_) => verifyNever(
          () => uploader.publish(any(), method: any(named: 'method'))),
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
      verify: (_) => verifyNever(
          () => uploader.publish(any(), method: any(named: 'method'))),
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'prepares a public drive, which has no drive key and needs none',
      build: cubitWith,
      setUp: () => insertDrive(privacy: DrivePrivacyTag.public),
      act: (cubit) => cubit.prepare(),
      expect: () => [
        isA<DriveStateCreationPreparing>(),
        // `getDriveKey` returns null for a drive with no `encryptedKey`, and
        // the cubit no longer reads anything into that. Whether an artifact
        // may be built is the service's answer, taken from the drive row.
        isA<DriveStateCreationReady>().having(
          (s) => s.artifact.isEncrypted,
          'artifact.isEncrypted',
          isFalse,
        ),
      ],
      // Prepared is still not published: the confirm button is the only thing
      // that reaches the uploader.
      verify: (_) => verifyNever(
          () => uploader.publish(any(), method: any(named: 'method'))),
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'refuses when nobody is logged in',
      build: cubitWith,
      setUp: () =>
          when(() => profileCubit.state).thenReturn(ProfileLoggingOut()),
      act: (cubit) => cubit.prepare(),
      expect: () => [
        isA<DriveStateCreationPreparing>(),
        isA<DriveStateCreationRefused>(),
      ],
      verify: (_) => verifyNever(
          () => uploader.publish(any(), method: any(named: 'method'))),
    );
  });

  group('cost', () {
    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'prices the artifact that was actually sealed, not an estimate of it',
      build: cubitWith,
      act: (cubit) => cubit.prepare(),
      verify: (cubit) {
        final ready = cubit.state as DriveStateCreationReady;
        final size = verify(() => costEstimator.estimate(
              sizeInBytes: captureAny(named: 'sizeInBytes'),
              wallet: any(named: 'wallet'),
              walletBalance: any(named: 'walletBalance'),
            )).captured.single;

        expect(size, ready.artifact.sizeInBytes);
      },
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'opens on Turbo when Turbo can pay',
      build: cubitWith,
      act: (cubit) => cubit.prepare(),
      verify: (cubit) => expect(
        (cubit.state as DriveStateCreationReady).method,
        UploadMethod.turbo,
      ),
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'opens on AR when there are no credits to pay with',
      build: cubitWith,
      setUp: () => when(() => costEstimator.estimate(
            sizeInBytes: any(named: 'sizeInBytes'),
            wallet: any(named: 'wallet'),
            walletBalance: any(named: 'walletBalance'),
          )).thenAnswer((_) async => _cost(sufficientTurboBalance: false)),
      act: (cubit) => cubit.prepare(),
      verify: (cubit) {
        final ready = cubit.state as DriveStateCreationReady;
        expect(ready.method, UploadMethod.ar);
        expect(ready.canPublish, isTrue);
      },
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'credits nobody can spend are not a way to pay',
      // Turbo unavailable — disabled in config, or it declined to quote a
      // price — while the wallet holds plenty of credits. Having the balance
      // is not the same as having the transport, and treating it as such
      // would enable a confirm button over an upload that cannot be sent.
      build: cubitWith,
      setUp: () => when(() => costEstimator.estimate(
            sizeInBytes: any(named: 'sizeInBytes'),
            wallet: any(named: 'wallet'),
            walletBalance: any(named: 'walletBalance'),
          )).thenAnswer((_) async => _cost(isTurboUploadPossible: false)),
      act: (cubit) async {
        await cubit.prepare();
        cubit.setUploadMethod(UploadMethod.turbo);
      },
      verify: (cubit) {
        final ready = cubit.state as DriveStateCreationReady;
        expect(ready.cost.sufficientTurboBalance, isTrue);
        expect(ready.canPublish, isFalse);
      },
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'an unavailable Turbo opens the modal on AR',
      build: cubitWith,
      setUp: () => when(() => costEstimator.estimate(
            sizeInBytes: any(named: 'sizeInBytes'),
            wallet: any(named: 'wallet'),
            walletBalance: any(named: 'walletBalance'),
          )).thenAnswer((_) async => _cost(isTurboUploadPossible: false)),
      act: (cubit) => cubit.prepare(),
      verify: (cubit) => expect(
        (cubit.state as DriveStateCreationReady).method,
        UploadMethod.ar,
      ),
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'switching the method re-decides whether the artifact is payable',
      build: cubitWith,
      setUp: () => when(() => costEstimator.estimate(
            sizeInBytes: any(named: 'sizeInBytes'),
            wallet: any(named: 'wallet'),
            walletBalance: any(named: 'walletBalance'),
          )).thenAnswer((_) async => _cost(sufficientTurboBalance: false)),
      act: (cubit) async {
        await cubit.prepare();
        cubit.setUploadMethod(UploadMethod.turbo);
      },
      verify: (cubit) {
        final ready = cubit.state as DriveStateCreationReady;
        expect(ready.method, UploadMethod.turbo);
        expect(ready.canPublish, isFalse);
      },
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'an artifact whose price cannot be established is never offered',
      build: cubitWith,
      setUp: () => when(() => costEstimator.estimate(
            sizeInBytes: any(named: 'sizeInBytes'),
            wallet: any(named: 'wallet'),
            walletBalance: any(named: 'walletBalance'),
          )).thenThrow(Exception('the gateway would not quote a price')),
      act: (cubit) => cubit.prepare(),
      expect: () => [
        isA<DriveStateCreationPreparing>(),
        isA<DriveStateCreationFailure>().having(
          (s) => s.message,
          'message',
          contains('cost of publishing could not be determined'),
        ),
      ],
      verify: (_) => verifyNever(
        () => uploader.publish(any(), method: any(named: 'method')),
      ),
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'a top-up re-reads the balances without touching the artifact',
      build: cubitWith,
      setUp: () {
        var call = 0;
        when(() => costEstimator.estimate(
              sizeInBytes: any(named: 'sizeInBytes'),
              wallet: any(named: 'wallet'),
              walletBalance: any(named: 'walletBalance'),
            )).thenAnswer(
          (_) async => _cost(sufficientTurboBalance: call++ > 0),
        );
      },
      act: (cubit) async {
        await cubit.prepare();
        cubit.setUploadMethod(UploadMethod.turbo);
        await cubit.refreshTurboBalance();
      },
      verify: (cubit) {
        final ready = cubit.state as DriveStateCreationReady;
        expect(ready.canPublish, isTrue);
        expect(ready.artifact.driveId, driveId);
      },
    );
  });

  group('publish', () {
    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'is ignored unless an artifact was prepared and shown',
      build: cubitWith,
      act: (cubit) => cubit.publish(),
      expect: () => <DriveStateCreationState>[],
      verify: (_) => verifyNever(
          () => uploader.publish(any(), method: any(named: 'method'))),
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'refuses an artifact no method can pay for, whatever the button says',
      build: cubitWith,
      setUp: () {
        when(() => costEstimator.estimate(
              sizeInBytes: any(named: 'sizeInBytes'),
              wallet: any(named: 'wallet'),
              walletBalance: any(named: 'walletBalance'),
            )).thenAnswer((_) async => _cost(
              sufficientArBalance: false,
              sufficientTurboBalance: false,
            ));
        when(() => uploader.publish(any(), method: any(named: 'method')))
            .thenAnswer(
          (_) async => const DriveStateUploadResult.published('tx-id'),
        );
      },
      act: (cubit) async {
        await cubit.prepare();
        await cubit.publish();
      },
      skip: 2,
      expect: () => <DriveStateCreationState>[],
      verify: (_) => verifyNever(
        () => uploader.publish(any(), method: any(named: 'method')),
      ),
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'publishes over the transport the user selected',
      build: cubitWith,
      setUp: () {
        when(() => costEstimator.estimate(
              sizeInBytes: any(named: 'sizeInBytes'),
              wallet: any(named: 'wallet'),
              walletBalance: any(named: 'walletBalance'),
            )).thenAnswer((_) async => _cost(sufficientTurboBalance: false));
        when(() => uploader.publish(any(), method: any(named: 'method')))
            .thenAnswer(
          (_) async => const DriveStateUploadResult.published('tx-id'),
        );
      },
      act: (cubit) async {
        await cubit.prepare();
        await cubit.publish();
      },
      verify: (_) => verify(
        () => uploader.publish(any(), method: UploadMethod.ar),
      ).called(1),
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'a free artifact goes over Turbo whatever the selector last said',
      build: cubitWith,
      setUp: () {
        when(() => costEstimator.estimate(
              sizeInBytes: any(named: 'sizeInBytes'),
              wallet: any(named: 'wallet'),
              walletBalance: any(named: 'walletBalance'),
            )).thenAnswer((_) async => _cost(
              freeStatus: FreeUploadStatus.free,
              sufficientArBalance: false,
              sufficientTurboBalance: false,
            ));
        when(() => uploader.publish(any(), method: any(named: 'method')))
            .thenAnswer(
          (_) async => const DriveStateUploadResult.published('tx-id'),
        );
      },
      act: (cubit) async {
        await cubit.prepare();
        cubit.setUploadMethod(UploadMethod.ar);
        await cubit.publish();
      },
      verify: (_) => verify(
        () => uploader.publish(any(), method: UploadMethod.turbo),
      ).called(1),
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'hands the prepared artifact to the uploader, once, on confirmation',
      build: cubitWith,
      setUp: () =>
          when(() => uploader.publish(any(), method: any(named: 'method')))
              .thenAnswer(
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
      verify: (_) =>
          verify(() => uploader.publish(any(), method: any(named: 'method')))
              .called(1),
    );

    blocTest<DriveStateCreationCubit, DriveStateCreationState>(
      'reports the seam refusing, as this build always does',
      build: cubitWith,
      setUp: () =>
          when(() => uploader.publish(any(), method: any(named: 'method')))
              .thenAnswer(
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
      setUp: () =>
          when(() => uploader.publish(any(), method: any(named: 'method')))
              .thenThrow(
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

  /// The modal that owns this cubit is dismissible, and both of its long steps
  /// are awaits: preparation seals a real payload, publishing is a network
  /// upload. A user who closes the dialog while either is in flight closes the
  /// cubit, and the await then returns into it.
  ///
  /// `emit` on a closed cubit throws, and in `prepare` the throw lands in the
  /// method's own `catch`, which emits again and throws again — that second one
  /// has nothing to catch it and surfaces as an unhandled asynchronous error.
  /// So these tests assert two things at once: the work finishes quietly, and
  /// nothing is emitted into a dialog that is gone.
  group('a modal dismissed mid-flight', () {
    /// Runs [act] and collects everything the cubit emits after [from].
    ///
    /// A `StateError` out of `emit` propagates straight out of the awaited
    /// call, so `await`ing the work is the whole assertion: if the cubit emits
    /// into itself after close, this rethrows and the test fails where the
    /// user would have seen a crash.
    Future<List<DriveStateCreationState>> statesEmittedDuring(
      DriveStateCreationCubit cubit,
      Future<void> Function() act,
    ) async {
      final seen = <DriveStateCreationState>[];
      final subscription = cubit.stream.listen(seen.add);

      await act();
      await subscription.cancel();

      return seen;
    }

    /// Hangs the cost estimate, and reports when the cubit has actually
    /// reached it. Without the second half the test races the earlier awaits
    /// in `prepare` and can close the cubit before the step it means to
    /// interrupt is even running.
    ({Completer<void> reached, Completer<DriveStatePublishCost> pricing})
        hangPricing() {
      final reached = Completer<void>();
      final pricing = Completer<DriveStatePublishCost>();

      when(() => costEstimator.estimate(
            sizeInBytes: any(named: 'sizeInBytes'),
            wallet: any(named: 'wallet'),
            walletBalance: any(named: 'walletBalance'),
          )).thenAnswer((_) {
        reached.complete();
        return pricing.future;
      });

      return (reached: reached, pricing: pricing);
    }

    ({Completer<void> reached, Completer<DriveStateUploadResult> upload})
        hangUpload() {
      final reached = Completer<void>();
      final upload = Completer<DriveStateUploadResult>();

      when(() => uploader.publish(any(), method: any(named: 'method')))
          .thenAnswer((_) {
        reached.complete();
        return upload.future;
      });

      return (reached: reached, upload: upload);
    }

    test('preparing does not emit into a cubit that was closed mid-flight',
        () async {
      final hung = hangPricing();
      final cubit = cubitWith();

      final seen = await statesEmittedDuring(cubit, () async {
        final preparing = cubit.prepare();
        await hung.reached.future;

        // The user closes the dialog while the artifact is being priced.
        await cubit.close();
        hung.pricing.complete(_cost());

        await preparing;
      });

      expect(
        seen,
        [isA<DriveStateCreationPreparing>()],
        reason: 'the ready state belongs to a modal that is no longer there',
      );
      verifyNever(() => uploader.publish(any(), method: any(named: 'method')));
    });

    test('preparing does not emit a failure into a closed cubit either',
        () async {
      // The same race on the path that fails, which is the one that throws
      // twice: once from the emit, and once from the catch that handles it —
      // and the second throw has nothing left to catch it.
      final hung = hangPricing();
      final cubit = cubitWith();

      final seen = await statesEmittedDuring(cubit, () async {
        final preparing = cubit.prepare();
        await hung.reached.future;

        await cubit.close();
        hung.pricing.completeError(
          StateError('the gateway would not price it'),
        );

        await preparing;
      });

      expect(seen, [isA<DriveStateCreationPreparing>()]);
    });

    test('publishing finishes, and reports into the log rather than the modal',
        () async {
      final hung = hangUpload();
      final cubit = cubitWith();
      await cubit.prepare();

      final seen = await statesEmittedDuring(cubit, () async {
        final publishing = cubit.publish();
        await hung.reached.future;

        // Dismissed while the artifact is on the wire. The upload is not
        // cancelled — it is paid for the moment it is posted — it simply has
        // nowhere left to report to.
        await cubit.close();
        hung.upload.complete(const DriveStateUploadResult.published('tx-id'));

        await publishing;
      });

      expect(
        seen,
        [isA<DriveStateCreationPublishing>()],
        reason: 'the published state has no modal left to reach',
      );
      verify(() => uploader.publish(any(), method: any(named: 'method')))
          .called(1);
    });

    test('a publish that fails after the modal closed is not emitted either',
        () async {
      final hung = hangUpload();
      final cubit = cubitWith();
      await cubit.prepare();

      final seen = await statesEmittedDuring(cubit, () async {
        final publishing = cubit.publish();
        await hung.reached.future;

        await cubit.close();
        hung.upload.completeError(
          StateError('the gateway rejected the chunk'),
        );

        await publishing;
      });

      expect(seen, [isA<DriveStateCreationPublishing>()]);
    });
  });

  group('the shipped uploader', () {
    test('publishes nothing, and says so', () async {
      final result = await const UnwiredDriveStateUploader().publish(
        _anyArtifact(),
        method: UploadMethod.turbo,
      );

      expect(result.isPublished, isFalse);
      expect(result.reason, contains('Nothing was uploaded'));
    });
  });
}

class _MockUploader extends Mock implements DriveStateUploader {}

class _MockCostEstimator extends Mock
    implements DriveStatePublishCostEstimator {}

/// A priced artifact both methods can afford, unless a test says otherwise.
DriveStatePublishCost _cost({
  bool sufficientArBalance = true,
  bool sufficientTurboBalance = true,
  bool isTurboUploadPossible = true,
  FreeUploadStatus freeStatus = FreeUploadStatus.notEligible,
}) =>
    DriveStatePublishCost(
      costEstimateAr: UploadCostEstimate.zero(),
      costEstimateTurbo: UploadCostEstimate.zero(),
      isTurboUploadPossible: isTurboUploadPossible,
      hasNoTurboBalance: false,
      arBalance: '1',
      turboCredits: '1',
      sufficientArBalance: sufficientArBalance,
      sufficientTurboBalance: sufficientTurboBalance,
      freeStatus: freeStatus,
    );

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

