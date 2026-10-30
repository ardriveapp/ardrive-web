import 'dart:async';

import 'package:ardrive/blocs/drive_create/first_drive.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/services/ethereum/ethereum_wallet.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/graphql_retry.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:clock/clock.dart';
import 'package:cryptography/cryptography.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../test_utils/utils.dart';

void main() {
  late ArDriveAuth mockArDriveAuth;
  late ArConnectService mockArConnectService;
  late EthereumProviderService mockEthereumProviderService;
  late SolanaProviderService mockSolanaProviderService;
  late UserRepository mockUserRepository;
  late TurboUploadService mockTurboUploadService;

  late DownloadService mockDownloadService;
  late ArweaveService mockArweaveService;
  late ProfileCubit mockProfileCubit;
  late ConfigService mockConfigService;
  final wallet = getTestWallet();

  registerFallbackValue(wallet);
  registerFallbackValue(Uint8List(10));

  LoginBloc createBloc() {
    return LoginBloc(
      arDriveAuth: mockArDriveAuth,
      arConnectService: mockArConnectService,
      ethereumProviderService: mockEthereumProviderService,
      solanaProviderService: mockSolanaProviderService,
      turboUploadService: mockTurboUploadService,
      arweaveService: mockArweaveService,
      downloadService: mockDownloadService,
      userRepository: mockUserRepository,
      profileCubit: mockProfileCubit,
      configService: mockConfigService,
    );
  }

  /// Every state [build]'s bloc emits for [act] once [elapse] has passed, in
  /// fake time: nothing waits on the wall clock, so a loaded machine can't
  /// make a wait too short.
  List<LoginState> statesInFakeTime(
    LoginBloc Function() build,
    void Function(LoginBloc bloc) act, {
    required Duration elapse,
    void Function(LoginBloc bloc, FakeAsync async)? during,
  }) {
    final states = <LoginState>[];
    fakeAsync((async) {
      final bloc = build();
      final subscription = bloc.stream.listen(states.add);
      act(bloc);
      during?.call(bloc, async);
      async.elapse(elapse);
      subscription.cancel();
      bloc.close();
      async.flushMicrotasks();
    });
    return states;
  }

  setUp(() {
    mockArDriveAuth = MockArDriveAuth();
    mockArConnectService = MockArConnectService();
    mockEthereumProviderService = MockEthereumProviderService();
    mockSolanaProviderService = MockSolanaProviderService();
    mockTurboUploadService = MockTurboUploadService();
    mockUserRepository = MockUserRepository();
    mockDownloadService = MockDownloadService();
    mockArweaveService = MockArweaveService();
    mockProfileCubit = MockProfileCubit();
    mockConfigService = MockConfigService();
  });

  group('AddWalletFile', () {
    /// Pages of the wallet's drives, as the lookup receives them.
    late StreamController<String> pages;

    setUp(() {
      when(() => mockArConnectService.isExtensionPresent())
          .thenAnswer((_) => false);
      pages = StreamController<String>.broadcast(sync: true);
      when(() => mockArweaveService.userDriveTxPageReceived)
          .thenAnswer((_) => pages.stream);
    });

    tearDown(() => pages.close());

    blocTest(
      'should emit the event to prompt password when user is an existing one',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
          ethereumProviderService: mockEthereumProviderService,
          solanaProviderService: mockSolanaProviderService,
          turboUploadService: mockTurboUploadService,
          arweaveService: mockArweaveService,
          downloadService: mockDownloadService,
          userRepository: mockUserRepository,
          profileCubit: mockProfileCubit,
          configService: mockConfigService,
        );
      },
      setUp: () {
        when(() => mockArDriveAuth.userHasPassword(any()))
            .thenAnswer((_) async => true);
        when(() => mockArDriveAuth.isExistingUser(any()))
            .thenAnswer((_) async => true);
      },
      act: (bloc) => bloc.add(AddWalletFile(wallet)),
      expect: () => [
        LoginLoadingIfUserAlreadyExists(),
        LoginLoadingIfUserAlreadyExistsSuccess(),
        predicate<PromptPassword>((p) {
          return p.showWalletCreated == false && p.mnemonic == null;
        })
      ],
    );

    blocTest(
      'should emit the event to secure wallet and show tutorials when user is not an existing one',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
          ethereumProviderService: mockEthereumProviderService,
          solanaProviderService: mockSolanaProviderService,
          turboUploadService: mockTurboUploadService,
          arweaveService: mockArweaveService,
          downloadService: mockDownloadService,
          userRepository: mockUserRepository,
          profileCubit: mockProfileCubit,
          configService: mockConfigService,
        );
      },
      setUp: () {
        // user doesn't exist
        when(() => mockArDriveAuth.userHasPassword(any()))
            .thenAnswer((_) async => false);
        when(() => mockArDriveAuth.isExistingUser(any()))
            .thenAnswer((_) async => false);
      },
      act: (bloc) => bloc.add(AddWalletFile(wallet)),
      expect: () => [
        LoginLoadingIfUserAlreadyExists(),
        LoginLoadingIfUserAlreadyExistsSuccess(),
        predicate<CreateNewPassword>((cnp) {
          return cnp.showWalletCreated == false &&
              cnp.mnemonic == null &&
              cnp.isNewUser == true;
        })
      ],
    );
    blocTest(
      'should emit the event to secure wallet and skip tutorials when user is an existing one with no private drives',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
          ethereumProviderService: mockEthereumProviderService,
          solanaProviderService: mockSolanaProviderService,
          turboUploadService: mockTurboUploadService,
          arweaveService: mockArweaveService,
          downloadService: mockDownloadService,
          userRepository: mockUserRepository,
          profileCubit: mockProfileCubit,
          configService: mockConfigService,
        );
      },
      setUp: () {
        // user doesn't exist
        when(() => mockArDriveAuth.userHasPassword(any()))
            .thenAnswer((_) async => false);
        when(() => mockArDriveAuth.isExistingUser(any()))
            .thenAnswer((_) async => true);
      },
      act: (bloc) => bloc.add(AddWalletFile(wallet)),
      expect: () => [
        LoginLoadingIfUserAlreadyExists(),
        LoginLoadingIfUserAlreadyExistsSuccess(),
        predicate<CreateNewPassword>((cnp) {
          return cnp.isNewUser == false &&
              cnp.showWalletCreated == false &&
              cnp.mnemonic == null;
        })
      ],
    );

    group('when a lookup fails', () {
      // In fake time against the real bound: a loaded machine can't stretch
      // a page past it, and the bound under test is the one that ships.
      const bound = LoginBloc.defaultWalletLookupTimeout;

      setUp(() {
        when(() => mockConfigService.config).thenReturn(AppConfig(
          allowedDataItemSizeForTurbo: 0,
          stripePublishableKey: '',
        ));
      });

      /// The states a chosen keyfile leads to once [after] has passed.
      List<LoginState> lookUp(Duration after) => statesInFakeTime(
            createBloc,
            (bloc) => bloc.add(AddWalletFile(wallet)),
            elapse: after,
          );

      final failedToTheGateway = [
        LoginLoadingIfUserAlreadyExists(),
        LoginLoadingIfUserAlreadyExistsSuccess(),
        isA<GatewayLoginFailure>(),
        isA<LoginLoading>(),
      ];

      // A page of the wallet's drives gets two GraphQL attempts, of 20 and
      // then 40 seconds, before a third. The bound has to outlast both, or a
      // page that stalls once fails the login while its retry is running.
      test('outlasts the first two attempts at a page', () {
        expect(
          bound,
          greaterThan(GraphQLRetry.attemptTimeoutFor(1) +
              GraphQLRetry.attemptTimeoutFor(2)),
        );
      });

      test('a page answered by its second attempt still logs in', () {
        when(() => mockArDriveAuth.userHasPassword(any()))
            .thenAnswer((_) => Future.delayed(
                  GraphQLRetry.attemptTimeoutFor(1) +
                      GraphQLRetry.attemptTimeoutFor(2) +
                      const Duration(seconds: 1),
                  () => true,
                ));

        expect(lookUp(bound * 2), [
          LoginLoadingIfUserAlreadyExists(),
          LoginLoadingIfUserAlreadyExistsSuccess(),
          isA<PromptPassword>(),
        ]);
      });

      // The hang: the dialog said "Loading wallet details..." for ever.
      test('a lookup that never answers closes the dialog with an error', () {
        when(() => mockArDriveAuth.userHasPassword(any()))
            .thenAnswer((_) => Completer<bool>().future);

        expect(lookUp(bound - const Duration(seconds: 1)),
            [LoginLoadingIfUserAlreadyExists()],
            reason: 'not before the bound');
        expect(lookUp(bound + const Duration(seconds: 1)), failedToTheGateway);
      });

      test('so does the drives lookup', () {
        when(() => mockArDriveAuth.userHasPassword(any()))
            .thenAnswer((_) async => false);
        when(() => mockArDriveAuth.isExistingUser(any()))
            .thenAnswer((_) => Completer<bool>().future);

        expect(lookUp(bound + const Duration(seconds: 1)), failedToTheGateway);
      });

      // A wallet with many drives takes many pages. The bound counts from
      // the last one, so a lookup longer than the bound still logs in.
      test('a lookup that keeps receiving pages is not cut off', () {
        final gap = bound - const Duration(seconds: 5);
        when(() => mockArDriveAuth.userHasPassword(any()))
            .thenAnswer((_) async {
          final address = await wallet.getAddress();
          for (var page = 0; page < 8; page++) {
            await Future<void>.delayed(gap);
            pages.add(address);
          }
          return true;
        });

        expect(lookUp(gap * 9), [
          LoginLoadingIfUserAlreadyExists(),
          LoginLoadingIfUserAlreadyExistsSuccess(),
          isA<PromptPassword>(),
        ]);
      });

      test('a lookup that stops receiving pages fails', () {
        when(() => mockArDriveAuth.userHasPassword(any()))
            .thenAnswer((_) async {
          final address = await wallet.getAddress();
          for (var page = 0; page < 3; page++) {
            await Future<void>.delayed(const Duration(seconds: 10));
            pages.add(address);
          }
          return Completer<bool>().future;
        });

        expect(
          lookUp(
              const Duration(seconds: 30) + bound + const Duration(seconds: 1)),
          failedToTheGateway,
        );
      });

      test("another wallet's pages don't keep a stalled lookup going", () {
        // Pages for another wallet keep arriving past the bound.
        when(() => mockArDriveAuth.userHasPassword(any()))
            .thenAnswer((_) async {
          for (var page = 0; page < 24; page++) {
            await Future<void>.delayed(const Duration(seconds: 10));
            if (!pages.isClosed) pages.add('another wallet');
          }
          return Completer<bool>().future;
        });

        expect(lookUp(bound + const Duration(seconds: 1)), failedToTheGateway);
      });

      blocTest<LoginBloc, LoginState>(
        'a lookup that throws closes the dialog with an error',
        build: createBloc,
        setUp: () {
          when(() => mockArDriveAuth.userHasPassword(any()))
              .thenThrow(Exception('the gateway is down'));
        },
        act: (bloc) => bloc.add(AddWalletFile(wallet)),
        expect: () => [
          LoginLoadingIfUserAlreadyExists(),
          LoginLoadingIfUserAlreadyExistsSuccess(),
          isA<LoginFailure>(),
          isA<LoginLoading>(),
        ],
      );

      blocTest<LoginBloc, LoginState>(
        'the wallet is not read from a file again',
        build: createBloc,
        setUp: () {
          when(() => mockArDriveAuth.userHasPassword(any()))
              .thenAnswer((_) async => true);
        },
        act: (bloc) => bloc.add(AddWalletFile(wallet)),
        verify: (_) {
          verify(() => mockArDriveAuth.userHasPassword(wallet)).called(1);
        },
      );
    });
  });

  group('LoginWithPassword', () {
    setUp(() {
      when(() => mockArConnectService.isExtensionPresent())
          .thenAnswer((_) => false);
      when(() => mockArConnectService.isWalletVersionSupported())
          .thenAnswer((_) => Future.value(true));
    });

    final loggedUser = User(
      password: 'password',
      wallet: wallet,
      walletAddress: 'walletAddress',
      walletBalance: BigInt.one,
      cipherKey: SecretKey([]),
      profileType: ProfileType.json,
      errorFetchingIOTokens: false,
    );
    blocTest(
      'should emit the event to show onboarding when user is not an existing one',
      build: () {
        return createBloc();
      },
      setUp: () {
        // login with success
        when(() => mockArDriveAuth.login(
              any(),
              'password',
              ProfileType.json,
            )).thenAnswer((_) async => loggedUser);
      },
      act: (bloc) async {
        bloc.profileType = ProfileType.json;

        bloc.add(LoginWithPassword(
            wallet: wallet, password: 'password', showWalletCreated: false));
      },
      expect: () =>
          [LoginCheckingPassword(), const TypeMatcher<LoginSuccess>()],
    );

    blocTest(
      'should emit success when arconnect and wallet doesnt mismatch',
      build: () {
        return createBloc();
      },
      setUp: () {
        // login with success
        when(() => mockArDriveAuth.login(
              any(),
              'password',
              ProfileType.arConnect,
            )).thenAnswer((_) async => loggedUser);

        when(() => mockArConnectService.getWalletAddress())
            .thenAnswer((invocation) => Future.value('some address'));
      },
      act: (bloc) async {
        bloc.lastKnownWalletAddress = 'some address';
        bloc.profileType = ProfileType.arConnect;

        bloc.add(LoginWithPassword(
          wallet: wallet,
          password: 'password',
          showWalletCreated: false,
        ));
      },
      expect: () =>
          [LoginCheckingPassword(), const TypeMatcher<LoginSuccess>()],
    );
    blocTest(
      'should emit failure when wallet mismatch',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
          ethereumProviderService: mockEthereumProviderService,
          solanaProviderService: mockSolanaProviderService,
          turboUploadService: mockTurboUploadService,
          arweaveService: mockArweaveService,
          downloadService: mockDownloadService,
          userRepository: mockUserRepository,
          profileCubit: mockProfileCubit,
          configService: mockConfigService,
        );
      },
      setUp: () {
        // login with success
        when(() => mockArDriveAuth.login(
              any(),
              'password',
              ProfileType.json,
            )).thenAnswer((_) async => loggedUser);

        when(() => mockArConnectService.getWalletAddress())
            .thenAnswer((invocation) => Future.value('some address'));
      },
      act: (bloc) async {
        // when an error occurs we go back to the last state, so use it to test
        bloc.emit(const PromptPassword());

        bloc.add(LoginWithPassword(
            wallet: wallet, password: 'password', showWalletCreated: false));
        bloc.profileType = ProfileType.arConnect;
      },
      expect: () => [
        const PromptPassword(),
        LoginCheckingPassword(),
        const TypeMatcher<LoginFailure>(),
        const PromptPassword()
      ],
    );

    blocTest(
      'should emit failure when an unknown error occurs',
      build: () {
        return createBloc();
      },
      setUp: () {
        // login with success
        when(() => mockArDriveAuth.login(
              any(),
              'password',
              ProfileType.json,
            )).thenThrow(Exception('some error'));
      },
      act: (bloc) async {
        // when an error occurs we go back to the last state, so use it to test
        bloc.emit(const PromptPassword());
        bloc.add(LoginWithPassword(
          wallet: wallet,
          password: 'password',
          showWalletCreated: false,
        ));
      },
      expect: () => [
        const PromptPassword(),
        LoginCheckingPassword(),
        const TypeMatcher<LoginUnknownFailure>()
      ],
    );
  });

  group('a password that opens none of the private drives', () {
    final loggedUser = User(
      password: 'typo',
      wallet: wallet,
      walletAddress: 'walletAddress',
      walletBalance: BigInt.one,
      cipherKey: SecretKey([]),
      profileType: ProfileType.json,
      errorFetchingIOTokens: false,
    );

    setUp(() {
      registerFallbackValue(ProfileType.json);
      when(() => mockArConnectService.isExtensionPresent())
          .thenAnswer((_) => false);
      when(() => mockArConnectService.isWalletVersionSupported())
          .thenAnswer((_) => Future.value(true));
      when(() => mockArConnectService.getWalletAddress())
          .thenAnswer((_) async => 'some address');
      when(() => mockArDriveAuth.login(any(), 'typo', any()))
          .thenThrow(const PasswordOpensNoDriveException());
      when(() => mockArDriveAuth.login(any(), 'right', any()))
          .thenAnswer((_) async => loggedUser);
      when(() =>
              mockArDriveAuth.login(any(), 'typo', any(), skipDriveCheck: true))
          .thenAnswer((_) async => loggedUser);
    });

    for (final type in [ProfileType.json, ProfileType.arConnect]) {
      final name = type == ProfileType.json ? 'a keyfile' : 'Wander';

      blocTest<LoginBloc, LoginState>(
        '$name: asks to try again or continue, never "Wrong password"',
        build: createBloc,
        act: (bloc) {
          bloc.profileType = type;
          bloc.lastKnownWalletAddress = 'some address';
          bloc.add(LoginWithPassword(
              wallet: wallet, password: 'typo', showWalletCreated: false));
        },
        expect: () => [
          LoginCheckingPassword(),
          const LoginPasswordOpensNoDrives(),
        ],
      );

      blocTest<LoginBloc, LoginState>(
        '$name: Try again goes back to the password; the right one signs in',
        build: createBloc,
        act: (bloc) async {
          bloc.profileType = type;
          bloc.lastKnownWalletAddress = 'some address';
          bloc.add(LoginWithPassword(
              wallet: wallet, password: 'typo', showWalletCreated: false));
          await Future<void>.delayed(Duration.zero);
          bloc.add(const RetrySignInPassword());
          await Future<void>.delayed(Duration.zero);
          bloc.add(LoginWithPassword(
              wallet: wallet, password: 'right', showWalletCreated: false));
        },
        expect: () => [
          LoginCheckingPassword(),
          const LoginPasswordOpensNoDrives(),
          const LoginPasswordRetry(),
          LoginCheckingPassword(),
          const TypeMatcher<LoginSuccess>(),
        ],
        verify: (_) => verifyNever(() => mockArDriveAuth.login(
            any(), any(), any(),
            sourceWalletAddress: any(named: 'sourceWalletAddress'),
            skipDriveCheck: true)),
      );

      blocTest<LoginBloc, LoginState>(
        '$name: Continue signs in, keeping the password, with the drives '
        'it didn\'t open locked',
        build: createBloc,
        act: (bloc) async {
          bloc.profileType = type;
          bloc.lastKnownWalletAddress = 'some address';
          bloc.add(LoginWithPassword(
              wallet: wallet, password: 'typo', showWalletCreated: false));
          await Future<void>.delayed(Duration.zero);
          bloc.add(const ContinueSignInWithLockedDrives());
        },
        expect: () => [
          LoginCheckingPassword(),
          const LoginPasswordOpensNoDrives(),
          LoginCheckingPassword(),
          const TypeMatcher<LoginSuccess>(),
        ],
        verify: (_) => verify(() => mockArDriveAuth.login(any(), 'typo', type,
            skipDriveCheck: true)).called(1),
      );
    }

    blocTest<LoginBloc, LoginState>(
      'Wander: Continue checks the wallet again; one switched while the '
      'dialog was open is a mismatch, not a sign-in',
      build: createBloc,
      act: (bloc) async {
        bloc.profileType = ProfileType.arConnect;
        bloc.lastKnownWalletAddress = 'some address';
        bloc.add(LoginWithPassword(
            wallet: wallet, password: 'typo', showWalletCreated: false));
        await Future<void>.delayed(Duration.zero);
        when(() => mockArConnectService.getWalletAddress())
            .thenAnswer((_) async => 'another address');
        bloc.add(const ContinueSignInWithLockedDrives());
      },
      expect: () => [
        LoginCheckingPassword(),
        const LoginPasswordOpensNoDrives(),
        LoginCheckingPassword(),
        const LoginFailure(WalletMismatchException()),
        isA<LoginState>(),
      ],
      verify: (_) => verifyNever(() => mockArDriveAuth.login(
          any(), any(), any(),
          sourceWalletAddress: any(named: 'sourceWalletAddress'),
          skipDriveCheck: true)),
    );

    blocTest<LoginBloc, LoginState>(
      'Try again or Continue with nothing pending does nothing',
      build: createBloc,
      act: (bloc) {
        bloc.add(const RetrySignInPassword());
        bloc.add(const ContinueSignInWithLockedDrives());
      },
      expect: () => <LoginState>[],
    );
  });

  group('CheckIfUserIsLoggedIn', () {
    setUp(() {
      when(() => mockArConnectService.isExtensionPresent())
          .thenAnswer((_) => false);
    });

    blocTest(
      'should emit the event to prompt password when user is an existing one and biometrics are disabled',
      build: () {
        return createBloc();
      },
      setUp: () {
        when(() => mockArDriveAuth.isUserLoggedIn())
            .thenAnswer((_) async => true);

        when(() => mockArDriveAuth.isBiometricsEnabled())
            .thenAnswer((invocation) => Future.value(false));
      },
      act: (bloc) async {
        bloc.add(const CheckIfUserIsLoggedIn());
      },
      expect: () => [LoginLoading(), const PromptPassword()],
    );

    blocTest(
      'should login with biometrics when user is an existing one and biometrics are enabled',
      build: () {
        return createBloc();
      },
      setUp: () {
        when(() => mockArDriveAuth.isUserLoggedIn())
            .thenAnswer((_) async => true);

        when(() => mockArDriveAuth.isBiometricsEnabled())
            .thenAnswer((invocation) => Future.value(true));

        when(() => mockArDriveAuth.unlockWithBiometrics(
              localizedReason: any(named: 'localizedReason'),
            )).thenAnswer((_) async => User(
              password: 'password',
              wallet: wallet,
              walletAddress: 'walletAddress',
              walletBalance: BigInt.one,
              cipherKey: SecretKey([]),
              profileType: ProfileType.json,
              errorFetchingIOTokens: false,
            ));
      },
      act: (bloc) async {
        bloc.add(const CheckIfUserIsLoggedIn());
      },
      expect: () => [LoginLoading(), const TypeMatcher<LoginSuccess>()],
    );

    // should emit PromptPassword when user is an existing one and biometrics are enabled but login with biometrics fails
    blocTest(
      'should emit PromptPassword when user is an existing one and biometrics are enabled but login with biometrics fails',
      build: () {
        return createBloc();
      },
      setUp: () {
        when(() => mockArDriveAuth.isUserLoggedIn())
            .thenAnswer((_) async => true);

        when(() => mockArDriveAuth.isBiometricsEnabled())
            .thenAnswer((invocation) => Future.value(true));

        when(() => mockArDriveAuth.unlockWithBiometrics(
              localizedReason: any(named: 'localizedReason'),
            )).thenThrow(Exception('some error'));
      },
      act: (bloc) async {
        bloc.add(const CheckIfUserIsLoggedIn());
      },
      expect: () => [LoginLoading(), const PromptPassword()],
    );

    blocTest(
      'should emit the initial event when user is not logged in',
      build: () {
        return createBloc();
      },
      setUp: () {
        // user doesn't exist
        when(() => mockArDriveAuth.isUserLoggedIn())
            .thenAnswer((_) async => false);

        when(() => mockArConnectService.isExtensionPresent())
            .thenAnswer((invocation) => false);
      },
      act: (bloc) async {
        bloc.add(const CheckIfUserIsLoggedIn());
      },
      expect: () => [
        LoginLoading(),
        const LoginLanding(),
      ],
    );

    // Log in pressed on the welcome panel while the check was still
    // running (the database opens slowly on a fresh load) went back to the
    // welcome panel when the check finished.
    test('a check that ends after Log in was pressed leaves Log in showing',
        () {
      when(() => mockArDriveAuth.isUserLoggedIn()).thenAnswer(
          (_) => Future.delayed(const Duration(milliseconds: 50), () => false));
      when(() => mockArConnectService.isExtensionPresent())
          .thenAnswer((invocation) => false);

      expect(
        statesInFakeTime(
          createBloc,
          (bloc) => bloc.add(const CheckIfUserIsLoggedIn()),
          during: (bloc, async) {
            async.elapse(const Duration(milliseconds: 10));
            bloc.add(const SelectLoginFlow(existingUser: true));
          },
          elapse: const Duration(milliseconds: 100),
        ),
        [
          LoginLoading(),
          isA<LoginInitial>()
              .having((s) => s.existingUserFlow, 'existingUserFlow', true),
        ],
      );
    });
  });

  group('UnlockUserWithPassword', () {
    setUp(() {
      when(() => mockArConnectService.isExtensionPresent())
          .thenAnswer((_) => false);
      when(() => mockArConnectService.isWalletVersionSupported())
          .thenAnswer((_) => Future.value(true));
    });

    final loggedUser = User(
      password: 'password',
      wallet: wallet,
      walletAddress: 'walletAddress',
      walletBalance: BigInt.one,
      cipherKey: SecretKey([]),
      profileType: ProfileType.json,
      errorFetchingIOTokens: false,
    );

    blocTest(
      'should emit success when user unlocks with success',
      build: () {
        return createBloc();
      },
      setUp: () {
        // user doesn't exist
        when(() => mockArDriveAuth.unlockUser(
              password: 'password',
            )).thenAnswer((_) async => loggedUser);
      },
      act: (bloc) async {
        bloc.add(const UnlockUserWithPassword(
          password: 'password',
        ));
        bloc.profileType = ProfileType.json;
      },
      expect: () =>
          [LoginCheckingPassword(), const TypeMatcher<LoginSuccess>()],
    );

    blocTest(
      'should emit failure when unlock fails',
      build: () {
        return createBloc();
      },
      setUp: () {
        // user doesn't exist
        when(() => mockArDriveAuth.unlockUser(
              password: 'password',
            )).thenThrow(WrongPasswordException('some error'));
      },
      act: (bloc) async {
        // when an error occurs we go back to the last state, so use it to test
        bloc.emit(const PromptPassword());

        bloc.add(const UnlockUserWithPassword(
          password: 'password',
        ));
        bloc.profileType = ProfileType.json;
      },
      expect: () => [
        const PromptPassword(),
        LoginCheckingPassword(),
        LoginPasswordFailed(),
      ],
    );
  });

  group('CreatePassword event', () {
    setUp(() {
      when(() => mockArConnectService.isExtensionPresent())
          .thenAnswer((_) => false);
    });

    final loggedUser = User(
      password: 'password',
      wallet: wallet,
      walletAddress: 'walletAddress',
      walletBalance: BigInt.one,
      cipherKey: SecretKey([]),
      profileType: ProfileType.json,
      errorFetchingIOTokens: false,
    );

    blocTest(
      'should emit success when user is created with success',
      build: () {
        return createBloc();
      },
      setUp: () {
        // user doesn't exist
        when(() => mockArDriveAuth.login(
              any(),
              'password',
              ProfileType.json,
            )).thenAnswer((_) async => loggedUser);
      },
      act: (bloc) async {
        bloc.add(CreatePassword(
            wallet: wallet,
            password: 'password',
            isNewUser: false,
            showWalletCreated: false));
        bloc.profileType = ProfileType.json;
      },
      expect: () => [
        LoginLoading(),
        const TypeMatcher<LoginSuccess>(),
        const TypeMatcher<LoginCreatePasswordComplete>()
      ],
    );

    blocTest(
      'should emit failure when user creation fails',
      build: () {
        return createBloc();
      },
      setUp: () {
        // user doesn't exist
        when(() => mockArDriveAuth.login(
              any(),
              'password',
              ProfileType.json,
            )).thenThrow(Exception('some error'));
      },
      act: (bloc) async {
        // when an error occurs we go back to the last state, so use it to test
        bloc.emit(const PromptPassword());

        bloc.add(CreatePassword(
            wallet: wallet,
            password: 'password',
            isNewUser: false,
            showWalletCreated: false));
        bloc.profileType = ProfileType.json;
      },
      expect: () => [
        const PromptPassword(),
        LoginLoading(),
        LoginCloseBlockingDialog(),
        const TypeMatcher<LoginFailure>(),
      ],
    );

    blocTest(
      'should emit success when user is created with success with ar connect',
      build: () {
        return createBloc();
      },
      setUp: () {
        when(() => mockArDriveAuth.login(
              any(),
              'password',
              ProfileType.arConnect,
            )).thenAnswer((_) async => loggedUser);
        when(() => mockArConnectService.getWalletAddress())
            .thenAnswer((invocation) => Future.value('some address'));
      },
      act: (bloc) async {
        bloc.lastKnownWalletAddress = 'some address';
        bloc.profileType = ProfileType.arConnect;

        bloc.add(CreatePassword(
          wallet: wallet,
          password: 'password',
          isNewUser: false,
          showWalletCreated: false,
        ));
      },
      expect: () => [
        LoginLoading(),
        const TypeMatcher<LoginSuccess>(),
        const TypeMatcher<LoginCreatePasswordComplete>()
      ],
    );

    blocTest(
      'should emit failure when wallet mismatch',
      build: () {
        return createBloc();
      },
      setUp: () {
        // user doesn't exist
        when(() => mockArDriveAuth.login(
              any(),
              'password',
              ProfileType.json,
            )).thenThrow(Exception('some error'));
        when(() => mockArConnectService.getWalletAddress())
            .thenAnswer((invocation) => Future.value('some another address'));
      },
      act: (bloc) async {
        bloc.lastKnownWalletAddress = 'some address';
        bloc.profileType = ProfileType.arConnect;
        // when an error occurs we go back to the last state, so use it to test
        bloc.emit(const PromptPassword());

        bloc.add(CreatePassword(
          wallet: wallet,
          password: 'password',
          showWalletCreated: false,
          isNewUser: false,
        ));
        bloc.profileType = ProfileType.json;
      },
      expect: () => [
        const PromptPassword(),
        LoginLoading(),
        LoginCloseBlockingDialog(),
        const TypeMatcher<LoginFailure>(),
      ],
    );
  });

  group('testing LoginBloc AddWalletFromArConnect event', () {
    setUp(() {
      when(() => mockArConnectService.isExtensionPresent())
          .thenAnswer((_) => false);
      when(() => mockArConnectService.isWalletVersionSupported())
          .thenAnswer((_) => Future.value(true));
    });

    blocTest(
      'should get the wallet from arconnect and emit prompt password',
      build: () {
        return createBloc();
      },
      setUp: () {
        when(() => mockArConnectService.connect())
            .thenAnswer((invocation) => Future.value(null));
        when(() => mockArConnectService.checkPermissions())
            .thenAnswer((invocation) => Future.value(true));
        when(() => mockArConnectService.getWalletAddress())
            .thenAnswer((invocation) => Future.value('walletAddress'));
        when(() => mockArDriveAuth.userHasPassword(any()))
            .thenAnswer((invocation) => Future.value(true));
      },
      act: (bloc) async {
        bloc.add(const AddWalletFromArConnect());
      },
      expect: () => [
        const LoginWaitingOnWallet(wallet: BrowserWallet.wander),
        const TypeMatcher<LoginInitial>(),
        const TypeMatcher<LoginShowBlockingDialog>(),
        LoginCloseBlockingDialog(),
        const TypeMatcher<PromptPassword>()
      ],
    );

    blocTest(
      'should emit a state to create new password when user never logged on ardrive',
      build: () {
        return createBloc();
      },
      setUp: () {
        when(() => mockArConnectService.connect())
            .thenAnswer((invocation) => Future.value(null));
        when(() => mockArConnectService.checkPermissions())
            .thenAnswer((invocation) => Future.value(true));
        when(() => mockArConnectService.getWalletAddress())
            .thenAnswer((invocation) => Future.value('walletAddress'));
        // new user but has public drives
        when(() => mockArDriveAuth.isExistingUser(any()))
            .thenAnswer((invocation) => Future.value(true));
        when(() => mockArDriveAuth.userHasPassword(any()))
            .thenAnswer((invocation) => Future.value(false));
      },
      act: (bloc) async {
        bloc.add(const AddWalletFromArConnect());
      },
      expect: () => [
        const LoginWaitingOnWallet(wallet: BrowserWallet.wander),
        const TypeMatcher<LoginInitial>(),
        const TypeMatcher<LoginShowBlockingDialog>(),
        LoginCloseBlockingDialog(),
        predicate<CreateNewPassword>((cnp) {
          return cnp.showWalletCreated == false &&
              cnp.mnemonic == null &&
              cnp.isNewUser == false;
        })
      ],
    );

    blocTest(
      'should emit a state to create new password when user never logged on ardrive and show tutorials if user has no drives',
      build: () {
        return createBloc();
      },
      setUp: () {
        when(() => mockArConnectService.connect())
            .thenAnswer((invocation) => Future.value(null));
        when(() => mockArConnectService.checkPermissions())
            .thenAnswer((invocation) => Future.value(true));
        when(() => mockArConnectService.getWalletAddress())
            .thenAnswer((invocation) => Future.value('walletAddress'));
        // new user and no drives
        when(() => mockArDriveAuth.isExistingUser(any()))
            .thenAnswer((invocation) => Future.value(false));
        when(() => mockArDriveAuth.userHasPassword(any()))
            .thenAnswer((invocation) => Future.value(false));
      },
      act: (bloc) async {
        bloc.add(const AddWalletFromArConnect());
      },
      expect: () => [
        const LoginWaitingOnWallet(wallet: BrowserWallet.wander),
        const TypeMatcher<LoginInitial>(),
        const TypeMatcher<LoginShowBlockingDialog>(),
        LoginCloseBlockingDialog(),
        predicate<CreateNewPassword>((cnp) {
          return cnp.showWalletCreated == false &&
              cnp.mnemonic == null &&
              cnp.isNewUser == true;
        })
      ],
    );

    blocTest(
      'should return silently when user doesnt grant permissions',
      build: () {
        return createBloc();
      },
      setUp: () {
        when(() => mockArConnectService.connect())
            .thenAnswer((invocation) => Future.value(null));
        // dont have permissions
        when(() => mockArConnectService.checkPermissions())
            .thenAnswer((invocation) => Future.value(false));
      },
      act: (bloc) async {
        bloc.add(const AddWalletFromArConnect());
      },
      // User rejected: back to Log in, no error dialog
      expect: () => [
        const LoginWaitingOnWallet(wallet: BrowserWallet.wander),
        const TypeMatcher<LoginInitial>(),
      ],
    );
  });

  group('testing ArDriveAuth ForgetWallet event', () {
    setUp(() {
      when(() => mockArConnectService.isExtensionPresent())
          .thenAnswer((_) => false);
    });

    blocTest(
      'should emit the initial login state and call logout when user is logged in',
      build: () {
        return createBloc();
      },
      setUp: () {
        when(() => mockArDriveAuth.isUserLoggedIn())
            .thenAnswer((invocation) => Future.value(true));
        when(() => mockArDriveAuth.logout())
            .thenAnswer((invocation) => Future.value(null));
        when(() => mockArConnectService.isExtensionPresent())
            .thenAnswer((invocation) => false);
        when(() => mockArConnectService.disconnect())
            .thenAnswer((invocation) => Future.value(null));
        when(() => mockSolanaProviderService.disconnect())
            .thenAnswer((_) => Future.value());
        when(() => mockProfileCubit.logoutProfile())
            .thenAnswer((_) => Future.value(null));
      },
      act: (bloc) async {
        bloc.add(const ForgetWallet());
      },
      verify: (_) {
        verify(() => mockSolanaProviderService.disconnect()).called(1);
      },
      expect: () => [const LoginLanding()],
    );
    blocTest(
      'should emit the initial login state and not call logout when user is not logged in',
      build: () {
        return createBloc();
      },
      setUp: () {
        // not logged in
        when(() => mockArDriveAuth.isUserLoggedIn())
            .thenAnswer((invocation) => Future.value(false));

        when(() => mockArConnectService.isExtensionPresent())
            .thenAnswer((invocation) => false);

        when(() => mockArConnectService.disconnect())
            .thenAnswer((invocation) => Future.value(null));
        when(() => mockSolanaProviderService.disconnect())
            .thenAnswer((_) => Future.value());
      },
      act: (bloc) async {
        bloc.add(const ForgetWallet());
      },
      verify: (bloc) => verifyNever(() => mockArDriveAuth.logout()),
      expect: () => [const LoginLanding()],
    );
  });

  group('testing ArDriveAuth FinishOnboarding event', () {
    setUp(() {
      when(() => mockArConnectService.isExtensionPresent())
          .thenAnswer((_) => false);
    });

    blocTest(
      'should emit the state to create password',
      build: () {
        return createBloc();
      },
      setUp: () {
        // not logged in
        when(() => mockArDriveAuth.isUserLoggedIn())
            .thenAnswer((invocation) => Future.value(true));
        when(() => mockArDriveAuth.currentUser).thenAnswer(
          (_) => User(
            password: 'password',
            wallet: getTestWallet(),
            walletAddress: 'walletAddress',
            walletBalance: BigInt.one,
            cipherKey: SecretKey([]),
            profileType: ProfileType.json,
            errorFetchingIOTokens: false,
          ),
        );
      },
      act: (bloc) async {
        bloc.add(FinishOnboarding(wallet: wallet));
      },
      expect: () => [const TypeMatcher<LoginSuccess>()],
    );
  });

  // group for test the UnLockWithBiometrics event
  group('testing LoginBloc UnLockWithBiometrics event', () {
    setUp(() {
      when(() => mockArConnectService.isExtensionPresent())
          .thenAnswer((_) => false);
    });

    final loggedUser = User(
      password: 'password',
      wallet: wallet,
      walletAddress: 'walletAddress',
      walletBalance: BigInt.one,
      cipherKey: SecretKey([]),
      profileType: ProfileType.json,
      errorFetchingIOTokens: false,
    );

    blocTest(
      'should emit the state to create password',
      build: () {
        return createBloc();
      },
      setUp: () {
        when(() => mockArDriveAuth.isUserLoggedIn())
            .thenAnswer((invocation) => Future.value(true));

        when(() => mockArDriveAuth.unlockWithBiometrics(
                localizedReason: any(named: 'localizedReason')))
            .thenAnswer((invocation) => Future.value(loggedUser));
      },
      act: (bloc) async {
        bloc.add(const UnLockWithBiometrics());
      },
      expect: () => [
        LoginLoading(),
        const TypeMatcher<LoginSuccess>(),
      ],
    );

    blocTest(
      'should emit a failure when biometrics fails',
      build: () {
        return createBloc();
      },
      setUp: () {
        when(() => mockArDriveAuth.isUserLoggedIn())
            .thenAnswer((invocation) => Future.value(true));

        when(() => mockArDriveAuth.unlockWithBiometrics(
                localizedReason: any(named: 'localizedReason')))
            .thenThrow(Exception('some error'));
      },
      act: (bloc) async {
        // when an error occurs we go back to the last state, so use it to test
        bloc.emit(const PromptPassword());

        bloc.add(const UnLockWithBiometrics());
      },
      expect: () => [
        const PromptPassword(),
        LoginLoading(),
        const TypeMatcher<LoginFailure>(),
        const PromptPassword(),
      ],
    );
  });

  group('testing LoginBloc LoginWithSolana event', () {
    final mockSignature = Uint8List.fromList(List.filled(64, 42));

    LoginBloc createSolanaBloc() {
      return LoginBloc(
        arDriveAuth: mockArDriveAuth,
        arConnectService: mockArConnectService,
        ethereumProviderService: mockEthereumProviderService,
        solanaProviderService: mockSolanaProviderService,
        turboUploadService: mockTurboUploadService,
        arweaveService: mockArweaveService,
        downloadService: mockDownloadService,
        userRepository: mockUserRepository,
        profileCubit: mockProfileCubit,
        configService: mockConfigService,
        walletFromMnemonic: (_) async => wallet,
      );
    }

    setUp(() {
      when(() => mockArConnectService.isExtensionPresent())
          .thenAnswer((_) => false);
      when(() => mockSolanaProviderService.isExtensionPresent())
          .thenReturn(true);
      when(() => mockSolanaProviderService.disconnect())
          .thenAnswer((_) => Future.value());
    });

    blocTest(
      'should emit prompt password when Solana user is an existing one',
      build: () => createSolanaBloc(),
      setUp: () {
        when(() => mockSolanaProviderService.connect(
                provider: any(named: 'provider')))
            .thenAnswer((_) async => const SolanaConnection(
                  address: 'SoLAddr123',
                  providerType: 'phantom',
                ));
        when(() => mockSolanaProviderService.signMessage(any()))
            .thenAnswer((_) async => mockSignature);
        when(() => mockArDriveAuth.userHasPassword(any()))
            .thenAnswer((_) async => true);
      },
      act: (bloc) async {
        bloc.add(const LoginWithSolana());
      },
      expect: () => [
        const LoginWaitingOnWallet(wallet: BrowserWallet.otherSolana),
        const LoginWaitingOnWallet(
          wallet: BrowserWallet.otherSolana,
          request: BrowserWalletRequest.signIn,
        ),
        const TypeMatcher<LoginInitial>(),
        const TypeMatcher<LoginShowBlockingDialog>(),
        LoginCloseBlockingDialog(),
        const TypeMatcher<PromptPassword>(),
      ],
    );

    blocTest(
      'should emit create new password with tutorials when Solana user is brand new',
      build: () => createSolanaBloc(),
      setUp: () {
        when(() => mockSolanaProviderService.connect(
                provider: any(named: 'provider')))
            .thenAnswer((_) async => const SolanaConnection(
                  address: 'SoLAddr123',
                  providerType: 'phantom',
                ));
        when(() => mockSolanaProviderService.signMessage(any()))
            .thenAnswer((_) async => mockSignature);
        when(() => mockArDriveAuth.userHasPassword(any()))
            .thenAnswer((_) async => false);
        when(() => mockArDriveAuth.isExistingUser(any()))
            .thenAnswer((_) async => false);
      },
      act: (bloc) async {
        bloc.add(const LoginWithSolana());
      },
      expect: () => [
        const LoginWaitingOnWallet(wallet: BrowserWallet.otherSolana),
        const LoginWaitingOnWallet(
          wallet: BrowserWallet.otherSolana,
          request: BrowserWalletRequest.signIn,
        ),
        const TypeMatcher<LoginInitial>(),
        const TypeMatcher<LoginShowBlockingDialog>(),
        LoginCloseBlockingDialog(),
        predicate<CreateNewPassword>((cnp) {
          return cnp.isNewUser == true && cnp.showWalletCreated == false;
        }),
      ],
    );

    blocTest(
      'should emit create new password without tutorials when Solana user has public drives',
      build: () => createSolanaBloc(),
      setUp: () {
        when(() => mockSolanaProviderService.connect(
                provider: any(named: 'provider')))
            .thenAnswer((_) async => const SolanaConnection(
                  address: 'SoLAddr123',
                  providerType: 'phantom',
                ));
        when(() => mockSolanaProviderService.signMessage(any()))
            .thenAnswer((_) async => mockSignature);
        when(() => mockArDriveAuth.userHasPassword(any()))
            .thenAnswer((_) async => false);
        when(() => mockArDriveAuth.isExistingUser(any()))
            .thenAnswer((_) async => true);
      },
      act: (bloc) async {
        bloc.add(const LoginWithSolana());
      },
      expect: () => [
        const LoginWaitingOnWallet(wallet: BrowserWallet.otherSolana),
        const LoginWaitingOnWallet(
          wallet: BrowserWallet.otherSolana,
          request: BrowserWalletRequest.signIn,
        ),
        const TypeMatcher<LoginInitial>(),
        const TypeMatcher<LoginShowBlockingDialog>(),
        LoginCloseBlockingDialog(),
        predicate<CreateNewPassword>((cnp) {
          return cnp.isNewUser == false && cnp.showWalletCreated == false;
        }),
      ],
    );

    blocTest(
      'should emit failure when no Solana wallet is detected',
      build: () => createSolanaBloc(),
      setUp: () {
        when(() => mockSolanaProviderService.isExtensionPresent())
            .thenReturn(false);
      },
      act: (bloc) async {
        bloc.add(const LoginWithSolana());
      },
      expect: () => [
        const TypeMatcher<LoginFailure>(),
      ],
    );

    blocTest(
      'should return silently when user rejects wallet connection',
      build: () => createSolanaBloc(),
      setUp: () {
        when(() => mockSolanaProviderService.connect(
            provider: any(named: 'provider'))).thenAnswer((_) async => null);
      },
      act: (bloc) async {
        bloc.add(const LoginWithSolana());
      },
      expect: () => [
        const LoginWaitingOnWallet(wallet: BrowserWallet.otherSolana),
        const TypeMatcher<LoginInitial>(),
      ],
    );

    blocTest(
      'should return silently when user rejects signature',
      build: () => createSolanaBloc(),
      setUp: () {
        when(() => mockSolanaProviderService.connect(
                provider: any(named: 'provider')))
            .thenAnswer((_) async => const SolanaConnection(
                  address: 'SoLAddr123',
                  providerType: 'phantom',
                ));
        when(() => mockSolanaProviderService.signMessage(any()))
            .thenThrow(Exception('User rejected signature request'));
      },
      act: (bloc) async {
        bloc.add(const LoginWithSolana());
      },
      expect: () => [
        const LoginWaitingOnWallet(wallet: BrowserWallet.otherSolana),
        const LoginWaitingOnWallet(
          wallet: BrowserWallet.otherSolana,
          request: BrowserWalletRequest.signIn,
        ),
        const TypeMatcher<LoginInitial>(),
      ],
    );
  });

  group('a new account', () {
    blocTest<LoginBloc, LoginState>(
      'shows Creating your account, then asks for a password',
      build: () => LoginBloc(
        arDriveAuth: mockArDriveAuth,
        arConnectService: mockArConnectService,
        ethereumProviderService: mockEthereumProviderService,
        solanaProviderService: mockSolanaProviderService,
        turboUploadService: mockTurboUploadService,
        arweaveService: mockArweaveService,
        downloadService: mockDownloadService,
        userRepository: mockUserRepository,
        profileCubit: mockProfileCubit,
        configService: mockConfigService,
        walletFromMnemonic: (_) async => wallet,
      ),
      setUp: () {
        when(() => mockArConnectService.isExtensionPresent())
            .thenAnswer((_) => false);
      },
      act: (bloc) => bloc.add(const CreateNewWallet()),
      expect: () => [
        isA<LoginCreatingAccount>(),
        isA<CreateNewPassword>()
            .having((s) => s.isNewUser, 'isNewUser', isTrue)
            .having((s) => s.showWalletCreated, 'showWalletCreated', isTrue)
            .having((s) => s.mnemonic?.split(' '), 'mnemonic', hasLength(12)),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'goes back to the landing panel when the key cannot be made',
      build: () => LoginBloc(
        arDriveAuth: mockArDriveAuth,
        arConnectService: mockArConnectService,
        ethereumProviderService: mockEthereumProviderService,
        solanaProviderService: mockSolanaProviderService,
        turboUploadService: mockTurboUploadService,
        arweaveService: mockArweaveService,
        downloadService: mockDownloadService,
        userRepository: mockUserRepository,
        profileCubit: mockProfileCubit,
        configService: mockConfigService,
        walletFromMnemonic: (_) async => throw Exception('no key'),
      ),
      setUp: () {
        when(() => mockArConnectService.isExtensionPresent())
            .thenAnswer((_) => false);
      },
      act: (bloc) => bloc.add(const CreateNewWallet()),
      expect: () => [
        isA<LoginCreatingAccount>(),
        isA<LoginFailure>(),
        isA<LoginLanding>(),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'asks again for the same wallet when the password step fails',
      build: () => LoginBloc(
        arDriveAuth: mockArDriveAuth,
        arConnectService: mockArConnectService,
        ethereumProviderService: mockEthereumProviderService,
        solanaProviderService: mockSolanaProviderService,
        turboUploadService: mockTurboUploadService,
        arweaveService: mockArweaveService,
        downloadService: mockDownloadService,
        userRepository: mockUserRepository,
        profileCubit: mockProfileCubit,
        configService: mockConfigService,
        walletFromMnemonic: (_) async => wallet,
      ),
      setUp: () {
        when(() => mockArConnectService.isExtensionPresent())
            .thenAnswer((_) => false);
        when(() => mockArDriveAuth.login(any(), any(), ProfileType.json,
                sourceWalletAddress: any(named: 'sourceWalletAddress')))
            .thenThrow(Exception('the gateway went away'));
      },
      act: (bloc) async {
        bloc.add(const CreateNewWallet());
        await Future<void>.delayed(Duration.zero);
        final created = bloc.state as CreateNewPassword;
        bloc.add(CreatePassword(
          password: 'river-lantern-orbit-maple-quiet-harbor',
          wallet: created.wallet,
          mnemonic: created.mnemonic,
          isNewUser: true,
          showWalletCreated: true,
        ));
        await Future<void>.delayed(Duration.zero);
        expect(bloc.hasSignUpToRetry, isTrue);
        // The page does this once the error has been read.
        bloc.add(const RetrySignUpPassword());
      },
      skip: 2,
      expect: () => [
        isA<LoginLoading>(),
        isA<LoginCloseBlockingDialog>(),
        isA<LoginFailure>(),
        isA<CreateNewPassword>()
            .having((s) => s.wallet, 'wallet', wallet)
            .having((s) => s.mnemonic?.split(' '), 'mnemonic', hasLength(12))
            .having((s) => s.retrying, 'retrying', isTrue),
      ],
      verify: (bloc) => expect(bloc.hasSignUpToRetry, isFalse),
    );

    group('first drive', () {
      late _MockFirstDrive firstDrive;

      LoginBloc signUpBloc() => LoginBloc(
            arDriveAuth: mockArDriveAuth,
            arConnectService: mockArConnectService,
            ethereumProviderService: mockEthereumProviderService,
            solanaProviderService: mockSolanaProviderService,
            turboUploadService: mockTurboUploadService,
            arweaveService: mockArweaveService,
            downloadService: mockDownloadService,
            userRepository: mockUserRepository,
            profileCubit: mockProfileCubit,
            configService: mockConfigService,
            walletFromMnemonic: (_) async => wallet,
            firstDrive: firstDrive,
          );

      setUp(() {
        firstDrive = _MockFirstDrive();
        when(() => firstDrive.request(any())).thenAnswer((_) async {});
        when(() => mockArConnectService.isExtensionPresent())
            .thenAnswer((_) => false);
        when(() => mockArDriveAuth.isUserLoggedIn())
            .thenAnswer((_) async => true);
        when(() => mockArDriveAuth.currentUser).thenAnswer(
          (_) => User(
            password: 'password',
            wallet: wallet,
            walletAddress: 'walletAddress',
            walletBalance: BigInt.one,
            cipherKey: SecretKey([]),
            profileType: ProfileType.json,
            errorFetchingIOTokens: false,
          ),
        );
      });

      blocTest<LoginBloc, LoginState>(
        'is asked for when a new account reaches the app',
        build: signUpBloc,
        act: (bloc) async {
          bloc.add(const CreateNewWallet());
          await Future<void>.delayed(Duration.zero);
          bloc.add(FinishOnboarding(wallet: wallet));
        },
        skip: 2,
        expect: () => [isA<LoginSuccess>()],
        verify: (_) async {
          final address = await wallet.getAddress();
          verify(() => firstDrive.request(address)).called(1);
        },
      );

      blocTest<LoginBloc, LoginState>(
        'is not asked for a wallet the user brought',
        build: signUpBloc,
        act: (bloc) => bloc.add(FinishOnboarding(wallet: wallet)),
        expect: () => [isA<LoginSuccess>()],
        verify: (_) => verifyNever(() => firstDrive.request(any())),
      );
    });
  });

  group('the log in screens', () {
    LoginBloc logInBloc() => LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
          ethereumProviderService: mockEthereumProviderService,
          solanaProviderService: mockSolanaProviderService,
          turboUploadService: mockTurboUploadService,
          arweaveService: mockArweaveService,
          downloadService: mockDownloadService,
          userRepository: mockUserRepository,
          profileCubit: mockProfileCubit,
          configService: mockConfigService,
          walletFromMnemonic: (_) async => wallet,
        );

    setUp(() {
      when(() => mockArConnectService.isExtensionPresent()).thenReturn(false);
      when(() => mockConfigService.config).thenReturn(AppConfig(
        allowedDataItemSizeForTurbo: 0,
        stripePublishableKey: '',
      ));
    });

    group('Sign up', () {
      void wallets({bool ar = false, bool eth = false, bool sol = false}) {
        when(() => mockArConnectService.isExtensionPresent()).thenReturn(ar);
        when(() => mockEthereumProviderService.isExtensionPresent())
            .thenReturn(eth);
        when(() => mockSolanaProviderService.isExtensionPresent())
            .thenReturn(sol);
      }

      for (final (name, ar, eth, sol) in [
        ('Wander', true, false, false),
        ('MetaMask', false, true, false),
        ('Phantom or Solflare', false, false, true),
      ]) {
        blocTest<LoginBloc, LoginState>(
          'with $name in the browser offers it before making an account',
          build: logInBloc,
          setUp: () => wallets(ar: ar, eth: eth, sol: sol),
          act: (bloc) => bloc.add(const StartSignUp()),
          expect: () => [
            predicate<LoginInitial>((s) => !s.existingUserFlow),
          ],
          verify: (bloc) => expect(bloc.existingUserFlow, isFalse),
        );
      }

      blocTest<LoginBloc, LoginState>(
        'with no wallet goes straight to making one, and says why',
        build: logInBloc,
        setUp: wallets,
        act: (bloc) => bloc.add(const StartSignUp()),
        expect: () => [
          const LoginCreatingAccount(noWalletFound: true),
          const TypeMatcher<CreateNewPassword>(),
        ],
      );

      blocTest<LoginBloc, LoginState>(
        'Create an account from the choice makes one without that line',
        build: logInBloc,
        setUp: () => wallets(ar: true),
        act: (bloc) async {
          bloc.add(const StartSignUp());
          await Future<void>.delayed(Duration.zero);
          bloc.add(const CreateNewWallet());
        },
        expect: () => [
          predicate<LoginInitial>((s) => !s.existingUserFlow),
          const LoginCreatingAccount(),
          const TypeMatcher<CreateNewPassword>(),
        ],
      );

      blocTest<LoginBloc, LoginState>(
        'a wallet cancelled from the choice goes back to the choice',
        build: logInBloc,
        setUp: () {
          wallets(eth: true);
          when(() => mockEthereumProviderService.connect())
              .thenAnswer((_) => Completer<EthereumWallet?>().future);
        },
        act: (bloc) async {
          bloc.add(const StartSignUp());
          await Future<void>.delayed(Duration.zero);
          bloc.add(const LoginWithMetamask());
          await Future<void>.delayed(Duration.zero);
          bloc.add(const CancelWalletLogin());
        },
        expect: () => [
          predicate<LoginInitial>((s) => !s.existingUserFlow),
          const LoginWaitingOnWallet(wallet: BrowserWallet.metamask),
          predicate<LoginInitial>((s) => !s.existingUserFlow),
        ],
      );

      test('remembers whether it came from Log in, for Back', () async {
        wallets(ar: true);
        final bloc = logInBloc();
        addTearDown(bloc.close);
        bloc.add(const StartSignUp(fromLogIn: true));
        await bloc.stream.first;
        expect(bloc.signUpFromLogIn, isTrue);
        bloc.add(const StartSignUp());
        await Future<void>.delayed(Duration.zero);
        expect(bloc.signUpFromLogIn, isFalse);
      });

      group('a wallet from the choice is a new account, from Log in not', () {
        void wanderWithoutPassword() {
          when(() => mockArConnectService.isWalletVersionSupported())
              .thenAnswer((_) async => true);
          when(() => mockArConnectService.checkPermissions())
              .thenAnswer((_) async => true);
          when(() => mockArConnectService.getWalletAddress())
              .thenAnswer((_) async => 'walletAddress');
          when(() => mockArDriveAuth.userHasPassword(any()))
              .thenAnswer((_) async => false);
          when(() => mockArDriveAuth.isExistingUser(any()))
              .thenAnswer((_) async => false);
        }

        void solanaWithoutPassword() {
          when(() => mockSolanaProviderService.connect(
                  provider: any(named: 'provider')))
              .thenAnswer((_) async => const SolanaConnection(
                  address: 'SoLAddr123', providerType: 'phantom'));
          when(() => mockSolanaProviderService.signMessage(any()))
              .thenAnswer((_) async => Uint8List(64));
          when(() => mockSolanaProviderService.disconnect(
              provider: any(named: 'provider'))).thenAnswer((_) async {});
          when(() => mockArDriveAuth.userHasPassword(any()))
              .thenAnswer((_) async => false);
          when(() => mockArDriveAuth.isExistingUser(any()))
              .thenAnswer((_) async => true);
        }

        for (final (name, setUpWallet, login) in [
          ('Wander', wanderWithoutPassword, const AddWalletFromArConnect()),
          (
            'Phantom',
            solanaWithoutPassword,
            const LoginWithSolana(provider: 'phantom')
          ),
        ]) {
          for (final fromSignUp in [true, false]) {
            blocTest<LoginBloc, LoginState>(
              '$name from ${fromSignUp ? 'Sign up' : 'Log in'}',
              build: logInBloc,
              setUp: () {
                wallets(ar: true, sol: true);
                setUpWallet();
              },
              act: (bloc) async {
                bloc.add(fromSignUp
                    ? const StartSignUp()
                    : const SelectLoginFlow(existingUser: true));
                await Future<void>.delayed(Duration.zero);
                bloc.add(login);
                await bloc.stream.firstWhere((s) => s is CreateNewPassword);
              },
              verify: (bloc) {
                final asked = bloc.state as CreateNewPassword;
                expect(asked.fromSignUp, fromSignUp);
              },
            );
          }
        }
      });

      blocTest<LoginBloc, LoginState>(
        'Log in from the choice is Log in again',
        build: logInBloc,
        setUp: () => wallets(ar: true),
        act: (bloc) async {
          bloc.add(const StartSignUp());
          await Future<void>.delayed(Duration.zero);
          bloc.add(const SelectLoginFlow(existingUser: true));
        },
        expect: () => [
          predicate<LoginInitial>((s) => !s.existingUserFlow),
          predicate<LoginInitial>((s) => s.existingUserFlow),
        ],
      );
    });

    group('the get-started link makes the same choice as Sign up', () {
      setUp(() {
        when(() => mockArDriveAuth.isUserLoggedIn())
            .thenAnswer((_) async => false);
        when(() => mockEthereumProviderService.isExtensionPresent())
            .thenReturn(false);
        when(() => mockSolanaProviderService.isExtensionPresent())
            .thenReturn(false);
      });

      blocTest<LoginBloc, LoginState>(
        'a wallet in the browser: the choice',
        build: logInBloc,
        setUp: () => when(() => mockArConnectService.isExtensionPresent())
            .thenReturn(true),
        act: (bloc) =>
            bloc.add(const CheckIfUserIsLoggedIn(gettingStarted: true)),
        expect: () => [
          LoginLoading(),
          predicate<LoginInitial>((s) => !s.existingUserFlow),
        ],
      );

      // In fake time: the wait for a wallet is a second of the clock, and on
      // a loaded machine a real second and a half was not always enough.
      List<LoginState> getStarted({required Duration after}) =>
          statesInFakeTime(
            logInBloc,
            (bloc) =>
                bloc.add(const CheckIfUserIsLoggedIn(gettingStarted: true)),
            elapse: after,
          );

      test('Wander injected a moment after the page loads: still the choice',
          () {
        DateTime? loaded;
        when(() => mockArConnectService.isExtensionPresent()).thenAnswer((_) {
          loaded ??= clock.now().add(const Duration(milliseconds: 300));
          return clock.now().isAfter(loaded!);
        });

        expect(getStarted(after: const Duration(seconds: 2)), [
          LoginLoading(),
          predicate<LoginInitial>((s) => !s.existingUserFlow),
        ]);
      });

      test('no wallet: straight to making one, saying why', () {
        when(() => mockArConnectService.isExtensionPresent()).thenReturn(false);

        // It looks for a wallet for a second first, and only then decides.
        expect(
          getStarted(after: const Duration(milliseconds: 900)),
          [LoginLoading()],
          reason: 'still looking for a wallet',
        );
        expect(getStarted(after: const Duration(seconds: 2)), [
          LoginLoading(),
          const LoginCreatingAccount(noWalletFound: true),
          const TypeMatcher<CreateNewPassword>(),
        ]);
      });
    });

    blocTest<LoginBloc, LoginState>(
      'Recovery phrase or keyfile opens the phrase panel, and Back the first',
      build: logInBloc,
      act: (bloc) async {
        bloc.add(const EnterSeedPhrase());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const SelectLoginFlow(existingUser: true));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const ShowLanding());
      },
      expect: () => [
        const LoginEnterRecoveryPhrase(),
        const TypeMatcher<LoginInitial>(),
        const LoginLanding(),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'a phrase with the gateway down says so, so it can be tried again',
      build: logInBloc,
      setUp: () => when(() => mockArDriveAuth.userHasPassword(any()))
          .thenThrow(const AuthenticationGatewayException()),
      act: (bloc) => bloc.add(const AddWalletFromSeedPhraseLogin('words')),
      expect: () => [
        LoginShowLoader(),
        LoginCloseBlockingDialog(),
        const TypeMatcher<GatewayLoginFailure>(),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'Cancel with nothing asked does nothing',
      build: logInBloc,
      act: (bloc) => bloc.add(const CancelWalletLogin()),
      expect: () => [],
    );

    group('Cancel while a wallet never answers', () {
      late void Function() wanderApproves;

      blocTest<LoginBloc, LoginState>(
        'Wander: back to Log in, and a late approval is ignored',
        build: logInBloc,
        setUp: () {
          final connect = Completer<void>();
          var asked = 0;
          when(() => mockArConnectService.isWalletVersionSupported())
              .thenAnswer((_) async => true);
          // No permission until the connect request, which hangs.
          when(() => mockArConnectService.checkPermissions())
              .thenAnswer((_) async => asked++ > 0);
          when(() => mockArConnectService.disconnect())
              .thenAnswer((_) async {});
          wanderApproves = connect.complete;
          when(() => mockArConnectService.connect())
              .thenAnswer((_) => connect.future);
          when(() => mockArConnectService.getWalletAddress())
              .thenAnswer((_) async => 'walletAddress');
        },
        act: (bloc) async {
          final waiting =
              bloc.stream.firstWhere((s) => s is LoginWaitingOnWallet);
          bloc.add(const AddWalletFromArConnect());
          await waiting;
          final back = bloc.stream.firstWhere((s) => s is LoginInitial);
          bloc.add(const CancelWalletLogin());
          await back;
          // The extension approves after Cancel.
          wanderApproves();
          await Future<void>.delayed(const Duration(milliseconds: 50));
        },
        expect: () => [
          const LoginWaitingOnWallet(wallet: BrowserWallet.wander),
          const TypeMatcher<LoginInitial>(),
        ],
        verify: (bloc) {
          verifyNever(() => mockArDriveAuth.userHasPassword(any()));
          expect(bloc.ignoreNextWaletSwitch, isFalse);
        },
      );

      blocTest<LoginBloc, LoginState>(
        'MetaMask: back to Log in',
        build: logInBloc,
        setUp: () {
          when(() => mockEthereumProviderService.isExtensionPresent())
              .thenReturn(true);
          when(() => mockEthereumProviderService.connect())
              .thenAnswer((_) => Completer<EthereumWallet?>().future);
        },
        act: (bloc) async {
          bloc.add(const LoginWithMetamask());
          await Future<void>.delayed(Duration.zero);
          bloc.add(const CancelWalletLogin());
        },
        expect: () => [
          const LoginWaitingOnWallet(wallet: BrowserWallet.metamask),
          const TypeMatcher<LoginInitial>(),
        ],
      );

      blocTest<LoginBloc, LoginState>(
        'Phantom: back to Log in, and the connection is dropped',
        build: logInBloc,
        setUp: () {
          when(() => mockSolanaProviderService.isExtensionPresent())
              .thenReturn(true);
          when(() => mockSolanaProviderService.disconnect(
              provider: any(named: 'provider'))).thenAnswer((_) async {});
          when(() => mockSolanaProviderService.connect(
                  provider: any(named: 'provider')))
              .thenAnswer((_) => Completer<SolanaConnection?>().future);
        },
        act: (bloc) async {
          bloc.add(const LoginWithSolana(provider: 'phantom'));
          await Future<void>.delayed(Duration.zero);
          bloc.add(const CancelWalletLogin());
        },
        expect: () => [
          const LoginWaitingOnWallet(wallet: BrowserWallet.phantom),
          const TypeMatcher<LoginInitial>(),
        ],
        verify: (_) => verify(
                () => mockSolanaProviderService.disconnect(provider: 'phantom'))
            .called(1),
      );
    });

    group('a late answer after Cancel goes no further', () {
      // Cancel goes back to Log in by itself, so these check what matters:
      // the wallet's late answer must not carry the log in on.
      void solana({
        required Future<SolanaConnection?> Function() connect,
        Future<Uint8List> Function()? sign,
      }) {
        when(() => mockSolanaProviderService.isExtensionPresent())
            .thenReturn(true);
        when(() => mockSolanaProviderService.disconnect(
            provider: any(named: 'provider'))).thenAnswer((_) async {});
        when(() => mockSolanaProviderService.disconnect())
            .thenAnswer((_) async {});
        when(() => mockSolanaProviderService.connect(
            provider: any(named: 'provider'))).thenAnswer((_) => connect());
        if (sign != null) {
          when(() => mockSolanaProviderService.signMessage(any()))
              .thenAnswer((_) => sign());
        }
      }

      // Answers held back until the test lets them through, after Cancel:
      // no race with a timer, however loaded the machine.
      final heldBack = <void Function()>[];
      setUp(heldBack.clear);

      Future<T> late<T>(T value) {
        final answer = Completer<T>();
        heldBack.add(() => answer.complete(value));
        return answer.future;
      }

      bool connecting(LoginState s) =>
          s is LoginWaitingOnWallet &&
          s.request == BrowserWalletRequest.connect;
      bool signing(LoginState s) =>
          s is LoginWaitingOnWallet && s.request == BrowserWalletRequest.signIn;

      /// Starts [login], presses Cancel once the panel reaches [at], then
      /// lets the wallet answer.
      Future<void> cancelThenAnswer(LoginBloc bloc, LoginEvent login,
          {bool Function(LoginState)? at}) async {
        final reached = bloc.stream.firstWhere(at ?? connecting);
        bloc.add(login);
        await reached;
        final back = bloc.stream.firstWhere((s) => s is LoginInitial);
        bloc.add(const CancelWalletLogin());
        await back;
        for (final answer in heldBack) {
          answer();
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      blocTest<LoginBloc, LoginState>(
        'MetaMask approving the connection',
        build: logInBloc,
        setUp: () {
          final ethWallet = _MockEthereumWallet();
          when(() => ethWallet.getAddress()).thenAnswer((_) async => '0xabc');
          when(() => mockEthereumProviderService.isExtensionPresent())
              .thenReturn(true);
          when(() => mockEthereumProviderService.connect())
              .thenAnswer((_) => late<EthereumWallet?>(ethWallet));
        },
        act: (bloc) => cancelThenAnswer(bloc, const LoginWithMetamask()),
        expect: () => [
          const LoginWaitingOnWallet(wallet: BrowserWallet.metamask),
          const TypeMatcher<LoginInitial>(),
        ],
        verify: (_) =>
            verifyNever(() => mockArweaveService.getFirstTxForWallet(any())),
      );

      blocTest<LoginBloc, LoginState>(
        'MetaMask signing',
        build: logInBloc,
        setUp: () {
          final ethWallet = _MockEthereumWallet();
          when(() => ethWallet.getAddress()).thenAnswer((_) async => '0xabc');
          when(() => ethWallet.sign(any()))
              .thenAnswer((_) => late(Uint8List(65)));
          when(() => mockEthereumProviderService.isExtensionPresent())
              .thenReturn(true);
          when(() => mockEthereumProviderService.connect())
              .thenAnswer((_) async => ethWallet);
        },
        act: (bloc) =>
            cancelThenAnswer(bloc, const LoginWithMetamask(), at: signing),
        expect: () => [
          const LoginWaitingOnWallet(wallet: BrowserWallet.metamask),
          const LoginWaitingOnWallet(
            wallet: BrowserWallet.metamask,
            request: BrowserWalletRequest.signIn,
          ),
          const TypeMatcher<LoginInitial>(),
        ],
        verify: (_) =>
            verifyNever(() => mockArweaveService.getFirstTxForWallet(any())),
      );

      blocTest<LoginBloc, LoginState>(
        'Phantom approving the connection: it is disconnected again',
        build: logInBloc,
        setUp: () => solana(
          connect: () => late<SolanaConnection?>(const SolanaConnection(
              address: 'SoLAddr123', providerType: 'phantom')),
          sign: () async => Uint8List(64),
        ),
        act: (bloc) =>
            cancelThenAnswer(bloc, const LoginWithSolana(provider: 'phantom')),
        expect: () => [
          const LoginWaitingOnWallet(wallet: BrowserWallet.phantom),
          const TypeMatcher<LoginInitial>(),
        ],
        verify: (_) {
          verifyNever(() => mockSolanaProviderService.signMessage(any()));
          verifyNever(() => mockArDriveAuth.userHasPassword(any()));
          // Once on Cancel, once when the late approval lands.
          verify(() =>
                  mockSolanaProviderService.disconnect(provider: 'phantom'))
              .called(2);
        },
      );

      blocTest<LoginBloc, LoginState>(
        'a late Phantom approval leaves a newer Phantom attempt connected',
        build: logInBloc,
        setUp: () {
          var connects = 0;
          const phantom =
              SolanaConnection(address: 'SoLAddr123', providerType: 'phantom');
          solana(
            connect: () => connects++ == 0
                // The first popup is approved only after the second try.
                ? late<SolanaConnection?>(phantom)
                : Future<SolanaConnection?>.value(phantom),
            sign: () => Completer<Uint8List>().future,
          );
        },
        act: (bloc) async {
          final reached = bloc.stream.firstWhere(connecting);
          bloc.add(const LoginWithSolana(provider: 'phantom'));
          await reached;
          final back = bloc.stream.firstWhere((s) => s is LoginInitial);
          bloc.add(const CancelWalletLogin());
          await back;
          final secondSigning = bloc.stream.firstWhere(signing);
          bloc.add(const LoginWithSolana(provider: 'phantom'));
          await secondSigning;
          // The first popup is approved now.
          for (final answer in heldBack) {
            answer();
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        },
        expect: () => [
          const LoginWaitingOnWallet(wallet: BrowserWallet.phantom),
          const TypeMatcher<LoginInitial>(),
          const LoginWaitingOnWallet(wallet: BrowserWallet.phantom),
          const LoginWaitingOnWallet(
            wallet: BrowserWallet.phantom,
            request: BrowserWalletRequest.signIn,
          ),
        ],
        verify: (_) {
          // Only Cancel's: the late approval must not drop the new attempt.
          verify(() =>
                  mockSolanaProviderService.disconnect(provider: 'phantom'))
              .called(1);
        },
      );

      blocTest<LoginBloc, LoginState>(
        'Solflare signing: only Solflare is disconnected',
        build: logInBloc,
        setUp: () => solana(
          connect: () async => const SolanaConnection(
              address: 'SoLAddr123', providerType: 'solflare'),
          sign: () => late(Uint8List(64)),
        ),
        act: (bloc) => cancelThenAnswer(
            bloc, const LoginWithSolana(provider: 'solflare'),
            at: signing),
        expect: () => [
          const LoginWaitingOnWallet(wallet: BrowserWallet.solflare),
          const LoginWaitingOnWallet(
            wallet: BrowserWallet.solflare,
            request: BrowserWalletRequest.signIn,
          ),
          const TypeMatcher<LoginInitial>(),
        ],
        verify: (_) {
          verifyNever(() => mockArDriveAuth.userHasPassword(any()));
          verify(() =>
                  mockSolanaProviderService.disconnect(provider: 'solflare'))
              .called(1);
          verifyNever(() => mockSolanaProviderService.disconnect());
        },
      );
    });

    group('an extension that throws goes back to Log in and says so', () {
      blocTest<LoginBloc, LoginState>(
        'Wander',
        build: logInBloc,
        setUp: () {
          when(() => mockArConnectService.isWalletVersionSupported())
              .thenAnswer((_) async => true);
          when(() => mockArConnectService.checkPermissions())
              .thenThrow(Exception('extension crashed'));
        },
        act: (bloc) => bloc.add(const AddWalletFromArConnect()),
        expect: () => [
          const LoginWaitingOnWallet(wallet: BrowserWallet.wander),
          const TypeMatcher<LoginInitial>(),
          const TypeMatcher<LoginFailure>(),
        ],
      );

      blocTest<LoginBloc, LoginState>(
        'MetaMask',
        build: logInBloc,
        setUp: () {
          final ethWallet = _MockEthereumWallet();
          when(() => ethWallet.getAddress())
              .thenThrow(Exception('extension crashed'));
          when(() => mockEthereumProviderService.isExtensionPresent())
              .thenReturn(true);
          when(() => mockEthereumProviderService.connect())
              .thenAnswer((_) async => ethWallet);
        },
        act: (bloc) => bloc.add(const LoginWithMetamask()),
        expect: () => [
          const LoginWaitingOnWallet(wallet: BrowserWallet.metamask),
          const TypeMatcher<LoginInitial>(),
          const TypeMatcher<LoginFailure>(),
        ],
      );
    });

    test('a file that is not a keyfile is refused', () async {
      final bloc = logInBloc();
      addTearDown(bloc.close);
      final file = await IOFile.fromData(
        Uint8List.fromList('not a keyfile'.codeUnits),
        name: 'notes.txt',
        lastModifiedDate: DateTime.now(),
      );
      expect(await bloc.validateAndReturnWalletFile(file), isNull);
    });

    group('reading a chosen keyfile', () {
      LoginBloc quickBloc() => LoginBloc(
            arDriveAuth: mockArDriveAuth,
            arConnectService: mockArConnectService,
            ethereumProviderService: mockEthereumProviderService,
            solanaProviderService: mockSolanaProviderService,
            turboUploadService: mockTurboUploadService,
            arweaveService: mockArweaveService,
            downloadService: mockDownloadService,
            userRepository: mockUserRepository,
            profileCubit: mockProfileCubit,
            configService: mockConfigService,
            keyfileReadTimeout: const Duration(milliseconds: 50),
          );

      // What the browser did: a read that failed never finished.
      test('a read that never finishes is unreadable, not a wait for ever',
          () async {
        final bloc = quickBloc();
        addTearDown(bloc.close);
        await expectLater(
          bloc.validateAndReturnWalletFile(_UnreadableFile.stuck()),
          throwsA(isA<KeyfileUnreadableException>()),
        );
      });

      test('a read that fails is unreadable', () async {
        final bloc = quickBloc();
        addTearDown(bloc.close);
        await expectLater(
          bloc.validateAndReturnWalletFile(_UnreadableFile.failing()),
          throwsA(isA<KeyfileUnreadableException>()),
        );
      });

      test('a keyfile gives its wallet', () async {
        final bloc = quickBloc();
        addTearDown(bloc.close);
        final file = await IOFile.fromData(
          Uint8List.fromList(getWalletString.codeUnits),
          name: 'key.json',
          lastModifiedDate: DateTime.now(),
        );
        final read = await bloc.validateAndReturnWalletFile(file);
        expect(await read!.getAddress(), await wallet.getAddress());
      });

      test('a file that is not text is not a keyfile, and is readable',
          () async {
        final bloc = quickBloc();
        addTearDown(bloc.close);
        final file = await IOFile.fromData(
          Uint8List.fromList([0xff, 0xfe, 0x00]),
          name: 'photo.jpg',
          lastModifiedDate: DateTime.now(),
        );
        expect(await bloc.validateAndReturnWalletFile(file), isNull);
      });
    });
  });
}

class _MockFirstDrive extends Mock implements FirstDrive {}

class _MockEthereumWallet extends Mock implements EthereumWallet {}

/// A keyfile the browser can't read: its read fails, or never finishes.
class _UnreadableFile extends Fake implements IOFile {
  _UnreadableFile.stuck() : _read = (() => Completer<Uint8List>().future);
  _UnreadableFile.failing()
      : _read = (() => Future.error(Exception('NotReadableError')));

  final Future<Uint8List> Function() _read;

  @override
  Future<Uint8List> readAsBytes() => _read();

  @override
  Future<String> readAsString() async => String.fromCharCodes(await _read());
}
