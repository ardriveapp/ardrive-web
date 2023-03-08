import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/services/services.dart';
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

  final wallet = getTestWallet();

  registerFallbackValue(wallet);
  registerFallbackValue(Uint8List(10));

  setUp(() {
    mockArDriveAuth = MockArDriveAuth();
    mockArConnectService = MockArConnectService();
  });

  group('AddWalletFile', () {
    blocTest(
      'should emit the event to prompt password when user is an existing one',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
        );
      },
      setUp: () {
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
        LoginLoading(),
        PromptPassword(walletFile: wallet),
      ],
    );
    blocTest(
      'should emit the event to show onboarding when user is not an existing one',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
        );
      },
      setUp: () {
        // user doesn't exist
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
        LoginLoading(),
        LoginOnBoarding(wallet),
      ],
    );
  });

  group('LoginWithPassword', () {
    final loggedUser = User(
      password: 'password',
      wallet: wallet,
      walletAddress: 'walletAddress',
      walletBalance: BigInt.one,
      cipherKey: SecretKey([]),
      profileType: ProfileType.json,
    );
    blocTest(
      'should emit the event to show onboarding when user is not an existing one',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
        );
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
          wallet: wallet,
          password: 'password',
        ));
      },
      expect: () => [LoginLoading(), const TypeMatcher<LoginSuccess>()],
    );

    blocTest(
      'should emit success when arconnect and wallet doesnt mismatch',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
        );
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
        ));
      },
      expect: () => [LoginLoading(), const TypeMatcher<LoginSuccess>()],
    );
    blocTest(
      'should emit failure when wallet mismatch',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
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
          wallet: wallet,
          password: 'password',
        ));
        bloc.profileType = ProfileType.arConnect;
      },
      expect: () => [
        const PromptPassword(),
        LoginLoading(),
        const TypeMatcher<LoginFailure>(),
        const PromptPassword()
      ],
    );

    blocTest(
      'should emit failure when an unknown error occurs',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
        );
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
        ));
      },
      expect: () => [
        const PromptPassword(),
        LoginLoading(),
        const TypeMatcher<LoginFailure>(),
        const PromptPassword()
      ],
    );
  });

  group('CheckIfUserIsLoggedIn', () {
    blocTest(
      'should emit the event to prompt password when user is an existing one',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
        );
      },
      setUp: () {
        when(() => mockArDriveAuth.isUserLoggedIn())
            .thenAnswer((_) async => true);
      },
      act: (bloc) async {
        bloc.add(const CheckIfUserIsLoggedIn());
      },
      expect: () => [LoginLoading(), const PromptPassword()],
    );

    blocTest(
      'should emit the initial event when user is not logged in',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
        );
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
      expect: () => [LoginLoading(), const LoginInitial(false)],
    );
  });

  group('UnlockUserWithPassword', () {
    final loggedUser = User(
      password: 'password',
      wallet: wallet,
      walletAddress: 'walletAddress',
      walletBalance: BigInt.one,
      cipherKey: SecretKey([]),
      profileType: ProfileType.json,
    );

    blocTest(
      'should emit success when user unlocks with success',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
        );
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
      expect: () => [LoginLoading(), const TypeMatcher<LoginSuccess>()],
    );

    blocTest(
      'should emit failure when unlock fails',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
        );
      },
      setUp: () {
        // user doesn't exist
        when(() => mockArDriveAuth.unlockUser(
              password: 'password',
            )).thenThrow(AuthenticationFailedException('some error'));
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
        LoginLoading(),
        const TypeMatcher<LoginFailure>(),
        const PromptPassword()
      ],
    );
  });

  group('CreatePassword event', () {
    final loggedUser = User(
      password: 'password',
      wallet: wallet,
      walletAddress: 'walletAddress',
      walletBalance: BigInt.one,
      cipherKey: SecretKey([]),
      profileType: ProfileType.json,
    );

    blocTest(
      'should emit success when user is created with success',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
        );
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
        ));
        bloc.profileType = ProfileType.json;
      },
      expect: () => [LoginLoading(), const TypeMatcher<LoginSuccess>()],
    );

    blocTest(
      'should emit failure when user creation fails',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
        );
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
        ));
        bloc.profileType = ProfileType.json;
      },
      expect: () => [
        const PromptPassword(),
        LoginLoading(),
        const TypeMatcher<LoginFailure>(),
        const PromptPassword()
      ],
    );

    blocTest(
      'should emit success when user is created with success with ar connect',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
        );
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
        ));
      },
      expect: () => [LoginLoading(), const TypeMatcher<LoginSuccess>()],
    );

    blocTest(
      'should emit failure when wallet mismatch',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
        );
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
        ));
        bloc.profileType = ProfileType.json;
      },
      expect: () => [
        const PromptPassword(),
        LoginLoading(),
        const TypeMatcher<LoginFailure>(),
        const PromptPassword()
      ],
    );
  });

  group('testing LoginBloc AddWalletFromArConnect event', () {
    blocTest(
      'should get the wallet from arconnect and emit prompt password',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
        );
      },
      setUp: () {
        when(() => mockArConnectService.connect())
            .thenAnswer((invocation) => Future.value(null));
        when(() => mockArConnectService.checkPermissions())
            .thenAnswer((invocation) => Future.value(true));
        when(() => mockArConnectService.getWalletAddress())
            .thenAnswer((invocation) => Future.value('walletAddress'));
        when(() => mockArDriveAuth.isExistingUser(any()))
            .thenAnswer((invocation) => Future.value(true));
      },
      act: (bloc) async {
        bloc.add(const AddWalletFromArConnect());
      },
      expect: () => [LoginLoading(), const TypeMatcher<PromptPassword>()],
    );

    blocTest(
      'should emit a state to create new password when user never logged on ardrive',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
        );
      },
      setUp: () {
        when(() => mockArConnectService.connect())
            .thenAnswer((invocation) => Future.value(null));
        when(() => mockArConnectService.checkPermissions())
            .thenAnswer((invocation) => Future.value(true));
        when(() => mockArConnectService.getWalletAddress())
            .thenAnswer((invocation) => Future.value('walletAddress'));
        // new user
        when(() => mockArDriveAuth.isExistingUser(any()))
            .thenAnswer((invocation) => Future.value(false));
      },
      act: (bloc) async {
        bloc.add(const AddWalletFromArConnect());
      },
      expect: () => [LoginLoading(), const TypeMatcher<LoginOnBoarding>()],
    );

    blocTest(
      'should emit a failure when user doesnt have permissions',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
        );
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
        LoginLoading(),
        const TypeMatcher<LoginFailure>(),
        const PromptPassword()
      ],
    );
  });

  group('testing ArDriveAuth ForgetWallet event', () {
    blocTest(
      'should emit the initial login state and call logout when user is logged in',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
        );
      },
      setUp: () {
        when(() => mockArDriveAuth.isUserLoggedIn())
            .thenAnswer((invocation) => Future.value(true));
        when(() => mockArDriveAuth.logout())
            .thenAnswer((invocation) => Future.value(null));
        when(() => mockArConnectService.isExtensionPresent())
            .thenAnswer((invocation) => false);
      },
      act: (bloc) async {
        bloc.add(const ForgetWallet());
      },
      expect: () => [const LoginInitial(false)],
    );
    blocTest(
      'should emit the initial login state and not call logout when user is not logged in',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
        );
      },
      setUp: () {
        // not logged in
        when(() => mockArDriveAuth.isUserLoggedIn())
            .thenAnswer((invocation) => Future.value(false));

        when(() => mockArConnectService.isExtensionPresent())
            .thenAnswer((invocation) => false);
      },
      act: (bloc) async {
        bloc.add(const ForgetWallet());
      },
      verify: (bloc) => verifyNever(() => mockArDriveAuth.logout()),
      expect: () => [const LoginInitial(false)],
    );
  });

  group('testing ArDriveAuth FinishOnboarding event', () {
    blocTest(
      'should emit the state to create password',
      build: () {
        return LoginBloc(
          arDriveAuth: mockArDriveAuth,
          arConnectService: mockArConnectService,
        );
      },
      act: (bloc) async {
        bloc.add(FinishOnboarding(wallet: wallet));
      },
      expect: () => [const TypeMatcher<CreatingNewPassword>()],
    );
  });
}
