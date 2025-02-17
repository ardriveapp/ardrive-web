import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../test_utils/utils.dart';

void main() {
  late ArDriveAuth mockArDriveAuth;
  late ArConnectService mockArConnectService;
  late EthereumProviderService mockEthereumProviderService;
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
      turboUploadService: mockTurboUploadService,
      arweaveService: mockArweaveService,
      downloadService: mockDownloadService,
      userRepository: mockUserRepository,
      profileCubit: mockProfileCubit,
      configService: mockConfigService,
    );
  }

  setUp(() {
    mockArDriveAuth = MockArDriveAuth();
    mockArConnectService = MockArConnectService();
    mockEthereumProviderService = MockEthereumProviderService();
    mockTurboUploadService = MockTurboUploadService();
    mockUserRepository = MockUserRepository();
    mockDownloadService = MockDownloadService();
    mockArweaveService = MockArweaveService();
    mockProfileCubit = MockProfileCubit();
    mockConfigService = MockConfigService();
  });

  group('AddWalletFile', () {
    setUp(() {
      when(() => mockArConnectService.isExtensionPresent())
          .thenAnswer((_) => false);
    });

    blocTest(
      'should emit the event to prompt password when user is an existing one',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
          ethereumProviderService: mockEthereumProviderService,
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
      act: (bloc) async {
        bloc.add(AddWalletFile(await IOFile.fromData(
          Uint8List.fromList(getWalletString.codeUnits),
          name: 'name',
          lastModifiedDate: DateTime.now(),
        )));
      },
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
      act: (bloc) async {
        bloc.add(AddWalletFile(await IOFile.fromData(
          Uint8List.fromList(getWalletString.codeUnits),
          name: 'name',
          lastModifiedDate: DateTime.now(),
        )));
      },
      expect: () => [
        LoginLoadingIfUserAlreadyExists(),
        LoginLoadingIfUserAlreadyExistsSuccess(),
        predicate<CreateNewPassword>((cnp) {
          return cnp.showWalletCreated == false &&
              cnp.mnemonic == null &&
              cnp.showTutorials == true;
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
      act: (bloc) async {
        bloc.add(AddWalletFile(await IOFile.fromData(
          Uint8List.fromList(getWalletString.codeUnits),
          name: 'name',
          lastModifiedDate: DateTime.now(),
        )));
      },
      expect: () => [
        LoginLoadingIfUserAlreadyExists(),
        LoginLoadingIfUserAlreadyExistsSuccess(),
        predicate<CreateNewPassword>((cnp) {
          return cnp.showTutorials == false &&
              cnp.showWalletCreated == false &&
              cnp.mnemonic == null;
        })
      ],
    );
  });

  group('LoginWithPassword', () {
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
  });

  group('UnlockUserWithPassword', () {
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
            showTutorials: false,
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
            showTutorials: false,
            showWalletCreated: false));
        bloc.profileType = ProfileType.json;
      },
      expect: () => [
        const PromptPassword(),
        LoginLoading(),
        const PromptPassword(),
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
          showTutorials: false,
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
          showTutorials: false,
        ));
        bloc.profileType = ProfileType.json;
      },
      expect: () => [
        const PromptPassword(),
        LoginLoading(),
        const PromptPassword(),
        const TypeMatcher<LoginFailure>(),
      ],
    );
  });

  group('testing LoginBloc AddWalletFromArConnect event', () {
    setUp(() {
      when(() => mockArConnectService.isExtensionPresent())
          .thenAnswer((_) => false);
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
        LoginLoadingIfUserAlreadyExists(),
        LoginLoadingIfUserAlreadyExistsSuccess(),
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
        LoginLoadingIfUserAlreadyExists(),
        LoginLoadingIfUserAlreadyExistsSuccess(),
        predicate<CreateNewPassword>((cnp) {
          return cnp.showWalletCreated == false &&
              cnp.mnemonic == null &&
              cnp.showTutorials == false;
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
        LoginLoadingIfUserAlreadyExists(),
        LoginLoadingIfUserAlreadyExistsSuccess(),
        predicate<CreateNewPassword>((cnp) {
          return cnp.showWalletCreated == false &&
              cnp.mnemonic == null &&
              cnp.showTutorials == true;
        })
      ],
    );

    blocTest(
      'should emit a failure when user doesnt have permissions',
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
        // when an error occurs we go back to the last state, so use it to test
        bloc.emit(const PromptPassword());

        bloc.add(const AddWalletFromArConnect());
      },
      expect: () => [
        const PromptPassword(),
        LoginLoadingIfUserAlreadyExists(),
        LoginLoadingIfUserAlreadyExistsSuccess(),
        const PromptPassword(),
        const TypeMatcher<LoginFailure>(),
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
        when(() => mockProfileCubit.logoutProfile())
            .thenAnswer((_) => Future.value(null));
      },
      act: (bloc) async {
        bloc.add(const ForgetWallet());
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
}
