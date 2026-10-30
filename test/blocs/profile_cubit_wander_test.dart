import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/utils.dart' show ownerToAddress;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

/// A saved Wander (ArConnect) account: unlocking it is a local password
/// check, and Wander is asked only when a write needs it.
void main() {
  const savedPublicKey = 'saved-public-key';
  const driveId = 'b3c8cb1b-4c3b-5d2c-9b3f-7e2b1c4d5e6f';

  late Database db;
  late MockArConnectService wander;
  late MockArDriveAuth auth;
  late StreamController<User?> authUsers;
  ProfileCubit? cubit;

  Future<void> saveWanderProfile() =>
      db.into(db.profiles).insert(ProfilesCompanion.insert(
            id: 'wallet-address',
            username: 'user',
            encryptedWallet: Uint8List(0),
            keySalt: Uint8List(0),
            walletPublicKey: savedPublicKey,
            encryptedPublicKey: Uint8List(0),
            profileType: ProfileType.arConnect.index,
          ));

  Future<void> insertDrive() =>
      db.into(db.drives).insert(DrivesCompanion.insert(
            id: driveId,
            rootFolderId: 'root-folder',
            ownerAddress: 'wallet-address',
            name: 'my drive',
            privacy: DrivePrivacyTag.public,
          ));

  ProfileCubit buildCubit() {
    final turboUploadService = MockTurboUploadService();
    when(() => turboUploadService.useTurboUpload).thenReturn(true);

    return cubit = ProfileCubit(
      turboUploadService: turboUploadService,
      profileDao: db.profileDao,
      db: db,
      tabVisibilitySingleton: TabVisibilitySingleton(),
      arDriveAuth: auth,
      arConnectService: wander,
    );
  }

  /// Wander as it is when locked and its unlock prompt has been closed:
  /// asked anything that needs it unlocked, it never answers.
  void wanderNeverAnswers() {
    when(() => wander.checkPermissions())
        .thenAnswer((_) => Completer<bool>().future);
    when(() => wander.getPublicKey())
        .thenAnswer((_) => Completer<String>().future);
    when(() => wander.getWalletAddress())
        .thenAnswer((_) => Completer<String>().future);
  }

  void wanderAnswers({String publicKey = savedPublicKey, bool allowed = true}) {
    when(() => wander.checkPermissions()).thenAnswer((_) async => allowed);
    when(() => wander.getPublicKey()).thenAnswer((_) async => publicKey);
    when(() => wander.getWalletAddress())
        .thenAnswer((_) async => ownerToAddress(publicKey));
  }

  setUp(() {
    ArConnectPrompt.reset();
    // Real time, kept short: drift's database doesn't run under fakeAsync.
    ArConnectPrompt.readTimeout = const Duration(milliseconds: 100);
    db = getTestDb();
    wander = MockArConnectService();
    when(() => wander.isExtensionPresent()).thenReturn(true);
    auth = MockArDriveAuth();
    authUsers = StreamController<User?>.broadcast();
    when(() => auth.onAuthStateChanged()).thenAnswer((_) => authUsers.stream);
    when(() => auth.logout()).thenAnswer((_) async {});
  });

  tearDown(() async {
    ArConnectPrompt.reset();
    await cubit?.close();
    cubit = null;
    await authUsers.close();
    await db.close();
  });

  group('starting with a saved Wander account', () {
    setUp(() async {
      await saveWanderProfile();
      await insertDrive();
    });

    test('reaches the unlock step without asking Wander, which never answers',
        () async {
      wanderNeverAnswers();

      buildCubit();
      await pumpEventQueue();

      expect(cubit!.state, isA<ProfilePromptLogIn>());
      verifyNever(() => wander.checkPermissions());
      verifyNever(() => wander.getPublicKey());
      verifyNever(() => wander.getWalletAddress());
      expect(await db.driveDao.allDrives().get(), hasLength(1));
    });

    test('keeps every drive when Wander is now on another wallet', () async {
      wanderAnswers(publicKey: 'other-public-key');

      buildCubit();
      await pumpEventQueue();

      expect(cubit!.state, isA<ProfilePromptLogIn>());
      expect(await db.driveDao.allDrives().get(), hasLength(1));
    });

    test('reaches the unlock step when Wander is not installed', () async {
      when(() => wander.isExtensionPresent()).thenReturn(false);

      buildCubit();
      await pumpEventQueue();

      expect(cubit!.state, isA<ProfilePromptLogIn>());
      expect(await db.driveDao.allDrives().get(), hasLength(1));
    });
  });

  group('checking the wallet before a write', () {
    late List<ArConnectUnavailableReason> prompts;

    setUp(() async {
      await saveWanderProfile();
      prompts = [];
      ArConnectPrompt.registerRetryPrompt((reason, _) async {
        prompts.add(reason);
        return false;
      });
    });

    test(
        'a Wander that never answers ends in the Try again prompt, and Cancel '
        'ends the wait', () async {
      wanderNeverAnswers();
      buildCubit();
      await pumpEventQueue();

      // A write must never wait forever: this would time out the test.
      await expectLater(
        cubit!.checkIfWalletMismatch(),
        throwsA(isA<ArConnectUnavailableException>().having(
            (e) => e.reason, 'reason', ArConnectUnavailableReason.noAnswer)),
      );
      expect(prompts, [ArConnectUnavailableReason.noAnswer]);
      expect(cubit!.state, isNot(isA<ProfileLoggingOut>()));
    });

    test('Try again asks Wander again and carries on once it is unlocked',
        () async {
      wanderNeverAnswers();
      buildCubit();
      await pumpEventQueue();

      ArConnectPrompt.registerRetryPrompt((reason, _) async {
        prompts.add(reason);
        // Unlocked while the prompt was up.
        wanderAnswers();
        return true;
      });

      expect(await cubit!.checkIfWalletMismatch(), isFalse);
      expect(prompts, [ArConnectUnavailableReason.noAnswer]);
    });

    test('says Wander is missing, with Try again, when it is not installed',
        () async {
      when(() => wander.isExtensionPresent()).thenReturn(false);
      buildCubit();
      await pumpEventQueue();

      await expectLater(
        cubit!.checkIfWalletMismatch(),
        throwsA(isA<ArConnectUnavailableException>().having((e) => e.reason,
            'reason', ArConnectUnavailableReason.notInstalled)),
      );
      expect(prompts, [ArConnectUnavailableReason.notInstalled]);
    });

    test('the same wallet is no mismatch', () async {
      wanderAnswers();
      buildCubit();
      await pumpEventQueue();

      expect(await cubit!.logoutIfWalletMismatch(), isFalse);
      expect(cubit!.state, isA<ProfilePromptLogIn>());
    });

    test('a Wander now on another wallet signs out at the first write',
        () async {
      wanderAnswers(publicKey: 'other-public-key');
      buildCubit();
      await pumpEventQueue();

      expect(await cubit!.logoutIfWalletMismatch(), isTrue);
      // All the way, so no Welcome back is left for the old wallet.
      verify(() => auth.logout()).called(1);
      expect(cubit!.state, isA<ProfileSignedOutForOtherWallet>());
      expect(cubit!.takeOtherWalletNotice(), isTrue);
      expect(cubit!.takeOtherWalletNotice(), isFalse);
    });

    group('a Wander that no longer lets ArDrive in', () {
      test('offers Reconnect, and carries on once it reconnected', () async {
        wanderAnswers(allowed: false);
        when(() => wander.connect()).thenAnswer((_) async {
          // Connecting gives the permissions back.
          wanderAnswers();
        });
        ArConnectPrompt.registerRetryPrompt((reason, _) async {
          prompts.add(reason);
          return true;
        });
        buildCubit();
        await pumpEventQueue();

        expect(await cubit!.logoutIfWalletMismatch(), isFalse);
        expect(prompts, [ArConnectUnavailableReason.noPermission]);
        verify(() => wander.connect()).called(1);
        verifyNever(() => auth.logout());
        expect(cubit!.state, isA<ProfilePromptLogIn>());
      });

      test('is not a switch: Cancel signs nobody out', () async {
        wanderAnswers(allowed: false);
        buildCubit();
        await pumpEventQueue();

        await expectLater(
          cubit!.logoutIfWalletMismatch(),
          throwsA(isA<ArConnectUnavailableException>().having((e) => e.reason,
              'reason', ArConnectUnavailableReason.noPermission)),
        );
        expect(prompts, [ArConnectUnavailableReason.noPermission]);
        verifyNever(() => wander.connect());
        verifyNever(() => auth.logout());
        expect(cubit!.state, isNot(isA<ProfileLoggingOut>()));
      });

      test('reconnected on another wallet signs out', () async {
        wanderAnswers(allowed: false);
        when(() => wander.connect()).thenAnswer((_) async {
          wanderAnswers(publicKey: 'other-public-key');
        });
        ArConnectPrompt.registerRetryPrompt((reason, _) async => true);
        buildCubit();
        await pumpEventQueue();

        expect(await cubit!.logoutIfWalletMismatch(), isTrue);
        verify(() => auth.logout()).called(1);
        expect(cubit!.state, isA<ProfileSignedOutForOtherWallet>());
      });
    });
  });

  group('Wander switching account', () {
    setUp(saveWanderProfile);

    test('to another wallet signs out once, and says so once', () async {
      buildCubit();
      await pumpEventQueue();
      final logouts = Completer<void>();
      when(() => auth.logout()).thenAnswer((_) => logouts.future);

      // Wander sends one event per tab and listener; all at once.
      final first = cubit!.onWanderSwitch('another-address');
      final second = cubit!.onWanderSwitch('another-address');
      await pumpEventQueue();
      logouts.complete();
      await Future.wait([first, second]);

      verify(() => auth.logout()).called(1);
      expect(cubit!.state, isA<ProfileSignedOutForOtherWallet>());
      expect(cubit!.takeOtherWalletNotice(), isTrue);
      expect(cubit!.takeOtherWalletNotice(), isFalse);
      verifyNever(() => wander.getWalletAddress());
    });

    test('back to the saved wallet changes nothing', () async {
      buildCubit();
      await pumpEventQueue();

      await cubit!.onWanderSwitch(await ownerToAddress(savedPublicKey));

      verifyNever(() => auth.logout());
      expect(cubit!.state, isA<ProfilePromptLogIn>());
    });

    test('with no address, as when ArDrive disconnects, changes nothing',
        () async {
      buildCubit();
      await pumpEventQueue();

      await cubit!.onWanderSwitch(null);

      verifyNever(() => auth.logout());
    });
  });

  group('the background wallet check', () {
    late List<ArConnectUnavailableReason> prompts;

    setUp(() async {
      await saveWanderProfile();
      prompts = [];
      ArConnectPrompt.registerRetryPrompt((reason, _) async {
        prompts.add(reason);
        return false;
      });
    });

    test('does not ask Wander before Wander has answered in this session',
        () async {
      wanderAnswers(publicKey: 'other-public-key');
      buildCubit();
      await pumpEventQueue();

      expect(await cubit!.logoutIfWalletMismatchInBackground(), isFalse);
      verifyNever(() => wander.getPublicKey());
      verifyNever(() => wander.checkPermissions());
    });

    test('notices another wallet once Wander has answered', () async {
      wanderAnswers();
      buildCubit();
      await pumpEventQueue();
      expect(await cubit!.checkIfWalletMismatch(), isFalse);

      wanderAnswers(publicKey: 'other-public-key');
      expect(await cubit!.logoutIfWalletMismatchInBackground(), isTrue);
      expect(cubit!.state, isA<ProfileLoggingOut>());
    });

    // Wander decrypts the wallet for its public key, which opens its unlock
    // window when it has locked since; its address it reads from storage.
    test('asks only what Wander answers without its password', () async {
      wanderAnswers();
      buildCubit();
      await pumpEventQueue();
      expect(await cubit!.checkIfWalletMismatch(), isFalse);

      expect(await cubit!.logoutIfWalletMismatchInBackground(), isFalse);
      verifyNever(() => wander.getPublicKey());
    });

    test('takes no answer as no mismatch and asks nobody', () async {
      wanderAnswers();
      buildCubit();
      await pumpEventQueue();
      expect(await cubit!.checkIfWalletMismatch(), isFalse);
      expect(ArConnectPrompt.hasAnswered, isTrue);

      wanderNeverAnswers();

      expect(await cubit!.logoutIfWalletMismatchInBackground(), isFalse);
      expect(prompts, isEmpty);
      expect(cubit!.state, isNot(isA<ProfileLoggingOut>()));
    });
  });
}
