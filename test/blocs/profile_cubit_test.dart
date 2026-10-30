import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/metadata_cache.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Selectable;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stash_memory/stash_memory.dart';

import '../test_utils/utils.dart';

class _MockSelectable<T> extends Mock implements Selectable<T> {}

class _MockDatabase extends Mock implements Database {}

class _MockArioSDK extends Mock implements ArioSDK {}

/// A [ProfileCubit] whose startup check finds no stored profile, so it rests
/// on [ProfilePromptAdd] until a test logs in.
ProfileCubit _buildProfileCubit(ArDriveAuth auth,
    {MockProfileDao? profileDao}) {
  final dao = profileDao ?? MockProfileDao();
  final noStoredProfile = _MockSelectable<Profile>();
  when(() => noStoredProfile.getSingleOrNull()).thenAnswer((_) async => null);
  when(() => dao.defaultProfile()).thenReturn(noStoredProfile);

  final turboUploadService = MockTurboUploadService();
  when(() => turboUploadService.useTurboUpload).thenReturn(true);

  return ProfileCubit(
    turboUploadService: turboUploadService,
    profileDao: dao,
    db: _MockDatabase(),
    tabVisibilitySingleton: TabVisibilitySingleton(),
    arDriveAuth: auth,
  );
}

User _user({String walletAddress = 'wallet-address', required int balance}) =>
    User(
      password: 'password',
      wallet: getTestWallet(),
      walletAddress: walletAddress,
      walletBalance: BigInt.from(balance),
      cipherKey: SecretKey([1, 2, 3]),
      profileType: ProfileType.json,
      errorFetchingIOTokens: false,
    );

BigInt? _shownBalance(ProfileCubit cubit) {
  final state = cubit.state;
  return state is ProfileLoggedIn ? state.user.walletBalance : null;
}

void main() {
  group('ProfileCubit', () {
    late MockArDriveAuth auth;
    late StreamController<User?> authUsers;
    late ProfileCubit cubit;

    setUp(() async {
      auth = MockArDriveAuth();
      authUsers = StreamController<User?>.broadcast();
      when(() => auth.onAuthStateChanged()).thenAnswer((_) => authUsers.stream);
      when(() => auth.currentUser)
          .thenThrow(const AuthenticationUserIsNotLoggedInException());

      cubit = _buildProfileCubit(auth);
      await pumpEventQueue();
    });

    tearDown(() async {
      await cubit.close();
      await authUsers.close();
    });

    test('shows a balance ArDriveAuth publishes after login', () async {
      await cubit.unlockDefaultProfile(_user(balance: 0), ProfileType.json);
      expect(_shownBalance(cubit), BigInt.zero);

      authUsers.add(_user(balance: 42));
      await pumpEventQueue();

      expect(_shownBalance(cubit), BigInt.from(42));
    });

    test('ignores a user published for another wallet', () async {
      await cubit.unlockDefaultProfile(_user(balance: 1), ProfileType.json);

      authUsers.add(_user(walletAddress: 'someone-else', balance: 42));
      await pumpEventQueue();

      expect(_shownBalance(cubit), BigInt.one);
    });

    test('is not logged in by a user ArDriveAuth publishes', () async {
      authUsers.add(_user(balance: 42));
      await pumpEventQueue();

      expect(cubit.state, isA<ProfilePromptAdd>());
    });

    test('stays put when ArDriveAuth publishes a logout', () async {
      await cubit.unlockDefaultProfile(_user(balance: 1), ProfileType.json);

      authUsers.add(null);
      await pumpEventQueue();

      expect(_shownBalance(cubit), BigInt.one);
    });

    test(
        'unlockDefaultProfile takes the balance ArDriveAuth already has when '
        'its refresh finished first', () async {
      when(() => auth.currentUser).thenReturn(_user(balance: 42));

      await cubit.unlockDefaultProfile(_user(balance: 0), ProfileType.json);

      expect(_shownBalance(cubit), BigInt.from(42));
    });

    test('refreshBalance emits the refreshed balance', () async {
      when(() => auth.currentUser).thenReturn(_user(balance: 1));
      await cubit.unlockDefaultProfile(_user(balance: 1), ProfileType.json);

      when(() => auth.refreshBalance()).thenAnswer((_) async {
        when(() => auth.currentUser).thenReturn(_user(balance: 2));
      });

      await cubit.refreshBalance();

      expect(_shownBalance(cubit), BigInt.two);
    });
  });

  // The whole chain the login takes: the real UserRepository and ArDriveAuth,
  // with only the network and the local profile store faked.
  group('login with a balance endpoint that is down', () {
    const password = 'password';
    final wallet = getTestWallet();

    late MockArweaveService arweave;
    late MockProfileDao profileDao;
    late ArDriveAuthImpl auth;
    late ProfileCubit cubit;

    setUp(() async {
      arweave = MockArweaveService();
      profileDao = MockProfileDao();

      final storedProfile = Profile(
        formatVersion: 1,
        id: 'id',
        username: '',
        encryptedWallet: Uint8List(0),
        keySalt: Uint8List(0),
        profileType: ProfileType.json.index,
        walletPublicKey: '',
        encryptedPublicKey: Uint8List(0),
      );
      when(() => profileDao.getDefaultProfile())
          .thenAnswer((_) async => storedProfile);
      when(() => profileDao.loadDefaultProfile(password))
          .thenAnswer((_) async => ProfileLoadDetails(
                details: storedProfile,
                wallet: wallet,
                key: SecretKey([1, 2, 3]),
                walletPublicKey: '',
              ));
      when(() => arweave.getPendingTxFees(any()))
          .thenAnswer((_) async => BigInt.zero);

      final biometrics = MockBiometricAuthentication();
      when(() => biometrics.isEnabled()).thenAnswer((_) async => false);

      auth = ArDriveAuthImpl(
        arweave: arweave,
        userRepository: UserRepository(profileDao, arweave, _MockArioSDK()),
        crypto: MockArDriveCrypto(),
        biometricAuthentication: biometrics,
        secureKeyValueStore: MockSecureKeyValueStore(),
        arConnectService: MockArConnectService(),
        databaseHelpers: MockDatabaseHelpers(),
        metadataCache: await MetadataCache.fromCacheStore(
          await newMemoryCacheStore(),
        ),
      );
    });

    tearDown(() => cubit.close());

    /// Answers the balance request with [first] at login and with [later] on
    /// every request after it.
    void answerBalance(
      Future<BigInt> Function() first,
      Future<BigInt> Function() later,
    ) {
      var calls = 0;
      when(() => arweave.getWalletBalance(any()))
          .thenAnswer((_) => calls++ == 0 ? first() : later());
    }

    test(
        'completes after the timeout when the balance never answers, then '
        'shows the real balance once the background refresh lands', () {
      fakeAsync((async) {
        cubit = _buildProfileCubit(auth, profileDao: profileDao);
        answerBalance(
          () => Completer<BigInt>().future,
          () => Future.delayed(
            const Duration(seconds: 2),
            () => BigInt.from(42),
          ),
        );

        User? loggedIn;
        auth.unlockUser(password: password).then((user) => loggedIn = user);

        async.elapse(const Duration(seconds: 6));
        expect(loggedIn, isNotNull, reason: 'login must not wait forever');
        expect(loggedIn!.walletBalance, BigInt.zero);

        cubit.unlockDefaultProfile(loggedIn!, ProfileType.json);
        async.flushMicrotasks();
        expect(_shownBalance(cubit), BigInt.zero);

        async.elapse(const Duration(seconds: 2));
        expect(_shownBalance(cubit), BigInt.from(42));
      });
    });

    test(
        'completes when the balance request fails, then shows the real '
        'balance once the background refresh lands', () async {
      cubit = _buildProfileCubit(auth, profileDao: profileDao);
      final laterBalance = Completer<BigInt>();
      answerBalance(
        () async => throw Exception('gateway unavailable'),
        () => laterBalance.future,
      );

      final loggedIn = await auth.unlockUser(password: password);
      expect(loggedIn.walletBalance, BigInt.zero);

      await cubit.unlockDefaultProfile(loggedIn, ProfileType.json);
      expect(_shownBalance(cubit), BigInt.zero);

      laterBalance.complete(BigInt.from(42));
      await pumpEventQueue();

      expect(_shownBalance(cubit), BigInt.from(42));
    });

    test('refreshBalance emits the new balance as soon as it completes',
        () async {
      cubit = _buildProfileCubit(auth, profileDao: profileDao);
      answerBalance(
        () async => BigInt.one,
        () async => BigInt.one,
      );

      final loggedIn = await auth.unlockUser(password: password);
      await pumpEventQueue();
      await cubit.unlockDefaultProfile(loggedIn, ProfileType.json);
      expect(_shownBalance(cubit), BigInt.one);

      when(() => arweave.getWalletBalance(any())).thenAnswer(
        (_) => Future.delayed(
          const Duration(milliseconds: 50),
          () => BigInt.two,
        ),
      );

      await cubit.refreshBalance();

      expect(_shownBalance(cubit), BigInt.two);
    });
  });
}
