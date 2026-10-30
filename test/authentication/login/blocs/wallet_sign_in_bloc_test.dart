import 'dart:async';
import 'dart:convert';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/blocs/drive_create/first_drive.dart';
import 'package:ardrive/device_unlock/domain/device_key.dart';
import 'package:ardrive/device_unlock/domain/device_secret_source.dart';
import 'package:ardrive/device_unlock/domain/device_unlocker.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/services/ethereum/ethereum_account.dart';
import 'package:ardrive/services/ethereum/provider/ethereum_provider_wallet.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/services/ethereum/ethereum_wallet.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webthree/credentials.dart';

import '../../../test_utils/locked_drive_fixtures.dart'
    show MemoryKeyValueStore;
import '../../../test_utils/utils.dart';

class _FakeSource extends Fake implements DeviceSecretSource {}

/// Signing in and Welcome back for the accounts a browser wallet opens,
/// with no password (the 3.0 password design, P3).
void main() {
  late MockArDriveAuth auth;
  late MockArConnectService arconnect;
  late MockEthereumProviderService ethereum;
  late MockSolanaProviderService solana;
  late MockArweaveService arweave;
  late MockTurboUploadService turbo;
  final wallet = getTestWallet();
  late User user;
  final ethWallet = EthereumProviderWallet(EthPrivateKey.fromHex(
      '4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318'));
  String? derivedFrom;

  setUpAll(() {
    registerFallbackValue(wallet);
    registerFallbackValue(ProfileType.json);
    registerFallbackValue(_FakeSource());
    registerFallbackValue(DataItem());
  });

  setUp(() async {
    auth = MockArDriveAuth();
    arconnect = MockArConnectService();
    ethereum = MockEthereumProviderService();
    solana = MockSolanaProviderService();
    arweave = MockArweaveService();
    turbo = MockTurboUploadService();
    when(() => turbo.postDataItem(
        dataItem: any(named: 'dataItem'),
        wallet: any(named: 'wallet'))).thenAnswer((_) async {});
    derivedFrom = null;
    user = User(
      password: '',
      wallet: wallet,
      walletAddress: await wallet.getAddress(),
      walletBalance: BigInt.zero,
      cipherKey: SecretKey(List.filled(32, 1)),
      profileType: ProfileType.arConnect,
      errorFetchingIOTokens: false,
    );
    when(() => arconnect.isExtensionPresent()).thenReturn(false);
    when(() => arconnect.isWalletVersionSupported())
        .thenAnswer((_) async => true);
    when(() => arconnect.checkPermissions()).thenAnswer((_) async => true);
    when(() => arconnect.getWalletAddress())
        .thenAnswer((_) async => user.walletAddress);
    when(() => solana.isExtensionPresent()).thenReturn(true);
    when(() => solana.disconnect(provider: any(named: 'provider')))
        .thenAnswer((_) async {});
    when(() => solana.detectProviders()).thenReturn(
        const SolanaLoginProviderDetection(
            hasAnyProvider: true, hasPhantom: true));
    when(() => ethereum.isExtensionPresent()).thenReturn(true);
    when(() => auth.getWalletAddress()).thenAnswer((_) async => null);
    when(() => auth.loginWithWallet(any(), any(), any(),
            sourceWalletAddress: any(named: 'sourceWalletAddress'),
            password: any(named: 'password'),
            skipDriveCheck: any(named: 'skipDriveCheck')))
        .thenAnswer((_) async => user);
  });

  LoginBloc bloc() => LoginBloc(
        arDriveAuth: auth,
        arConnectService: arconnect,
        ethereumProviderService: ethereum,
        solanaProviderService: solana,
        turboUploadService: turbo,
        arweaveService: arweave,
        downloadService: MockDownloadService(),
        userRepository: MockUserRepository(),
        profileCubit: MockProfileCubit(),
        configService: MockConfigService(),
        walletFromMnemonic: (mnemonic) async {
          derivedFrom = mnemonic;
          return wallet;
        },
      );

  DeviceSecretSource capturedSource() =>
      verify(() => auth.loginWithWallet(any(), any(), captureAny(),
              sourceWalletAddress: any(named: 'sourceWalletAddress'),
              password: any(named: 'password'),
              skipDriveCheck: any(named: 'skipDriveCheck'))).captured.single
          as DeviceSecretSource;

  group('sign in', () {
    blocTest<LoginBloc, LoginState>(
      'Wander: one approval for the device key, no password and no drive '
      'check',
      build: bloc,
      act: (bloc) => bloc.add(const AddWalletFromArConnect()),
      expect: () => [
        const LoginWaitingOnWallet(wallet: BrowserWallet.wander),
        const LoginWaitingOnWallet(
          wallet: BrowserWallet.wander,
          request: BrowserWalletRequest.signIn,
        ),
        isA<LoginSuccess>(),
      ],
      verify: (_) {
        expect(capturedSource().method, DeviceUnlockMethod.wander);
        verifyNever(() => auth.userHasPassword(any()));
        verifyNever(() => auth.login(any(), any(), any(),
            sourceWalletAddress: any(named: 'sourceWalletAddress'),
            skipDriveCheck: any(named: 'skipDriveCheck')));
      },
    );

    blocTest<LoginBloc, LoginState>(
      'Wander: saying no goes back to Log in, with no error and nothing saved',
      build: bloc,
      setUp: () => when(() => auth.loginWithWallet(any(), any(), any(),
              sourceWalletAddress: any(named: 'sourceWalletAddress'),
              password: any(named: 'password'),
              skipDriveCheck: any(named: 'skipDriveCheck')))
          .thenThrow(
              const DeviceUnlockRefusedException(DeviceUnlockStatus.declined)),
      act: (bloc) => bloc.add(const AddWalletFromArConnect()),
      expect: () => [
        const LoginWaitingOnWallet(wallet: BrowserWallet.wander),
        const LoginWaitingOnWallet(
          wallet: BrowserWallet.wander,
          request: BrowserWalletRequest.signIn,
        ),
        isA<LoginInitial>(),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'Phantom: the sign-in signature is the device key; no password',
      build: bloc,
      setUp: () {
        when(() => solana.connect(provider: any(named: 'provider'))).thenAnswer(
            (_) async => const SolanaConnection(
                address: 'So1Addr', providerType: 'phantom'));
        when(() => solana.signMessage(any()))
            .thenAnswer((_) async => Uint8List.fromList(List.filled(64, 3)));
      },
      act: (bloc) => bloc.add(const LoginWithSolana(provider: 'phantom')),
      expect: () => [
        const LoginWaitingOnWallet(wallet: BrowserWallet.phantom),
        const LoginWaitingOnWallet(
          wallet: BrowserWallet.phantom,
          request: BrowserWalletRequest.signIn,
        ),
        isA<LoginInitial>(),
        isA<LoginShowBlockingDialog>(),
        isA<LoginCloseBlockingDialog>(),
        isA<LoginSuccess>(),
      ],
      verify: (_) {
        expect(capturedSource().method, DeviceUnlockMethod.solana);
        verifyNever(() => auth.userHasPassword(any()));
      },
    );

    group('MetaMask', () {
      late String accountAddress;

      setUp(() async {
        when(() => ethereum.connect()).thenAnswer((_) async => ethWallet);
        when(() => auth.isExistingUser(any())).thenAnswer((_) async => true);
        accountAddress = await wallet.getAddress();
      });

      void records(EthereumAccountRecord? record) =>
          when(() => arweave.findEthereumAccountRecord(any()))
              .thenAnswer((_) async => record);

      void neverSignedIn() =>
          verifyNever(() => auth.loginWithWallet(any(), any(), any(),
              sourceWalletAddress: any(named: 'sourceWalletAddress'),
              password: any(named: 'password'),
              skipDriveCheck: any(named: 'skipDriveCheck')));

      List<DataItem> posted() => verify(() => turbo.postDataItem(
          dataItem: captureAny(named: 'dataItem'),
          wallet: any(named: 'wallet'))).captured.cast<DataItem>();

      Map<String, String> tagsOf(DataItem item) => {
            for (final tag in item.tags)
              utf8.decode(decodeBase64ToBytes(tag.name)):
                  utf8.decode(decodeBase64ToBytes(tag.value)),
          };

      blocTest<LoginBloc, LoginState>(
        'a version 2 marker whose address the account message derives: '
        'signed in with no password, and no marker posted again',
        build: bloc,
        setUp: () =>
            records(EthereumV2Marker('marker', accountAddress: accountAddress)),
        act: (bloc) => bloc.add(const LoginWithMetamask()),
        wait: const Duration(milliseconds: 300),
        verify: (bloc) async {
          expect(bloc.state, isA<LoginSuccess>());
          expect(derivedFrom, await deriveEthereumAccountMnemonic(ethWallet));
          final captured = verify(() => auth.loginWithWallet(
              any(), any(), captureAny(),
              sourceWalletAddress: any(named: 'sourceWalletAddress'),
              password: captureAny(named: 'password'),
              skipDriveCheck: any(named: 'skipDriveCheck'))).captured;
          expect((captured[0] as DeviceSecretSource).method,
              DeviceUnlockMethod.ethereum);
          expect(captured[1], isEmpty);
          verifyNever(() => turbo.postDataItem(
              dataItem: any(named: 'dataItem'), wallet: any(named: 'wallet')));
        },
      );

      blocTest<LoginBloc, LoginState>(
        'a version 2 marker for another address: the wallet signs '
        'differently, and nothing opens',
        build: bloc,
        setUp: () =>
            records(const EthereumV2Marker('marker', accountAddress: 'other')),
        act: (bloc) => bloc.add(const LoginWithMetamask()),
        wait: const Duration(milliseconds: 300),
        verify: (bloc) {
          expect(
              bloc.state,
              isA<LoginFailure>().having((s) => s.error, 'error',
                  isA<EthereumWalletSignsDifferently>()));
          neverSignedIn();
        },
      );

      blocTest<LoginBloc, LoginState>(
        'a version 1 record: an existing account, whose password is asked',
        build: bloc,
        setUp: () => records(const EthereumV1Record('first-tx')),
        act: (bloc) => bloc.add(const LoginWithMetamask()),
        wait: const Duration(milliseconds: 200),
        verify: (bloc) {
          expect(bloc.state, isA<PromptPassword>());
          expect(derivedFrom, isNull);
          neverSignedIn();
        },
      );

      blocTest<LoginBloc, LoginState>(
        'a record lookup that fails is never taken for a new account',
        build: bloc,
        setUp: () => when(() => arweave.findEthereumAccountRecord(any()))
            .thenThrow(Exception('gateway unreachable')),
        act: (bloc) => bloc.add(const LoginWithMetamask()),
        wait: const Duration(milliseconds: 200),
        verify: (bloc) {
          expect(bloc.state, isA<LoginFailure>());
          expect(derivedFrom, isNull);
          neverSignedIn();
        },
      );

      blocTest<LoginBloc, LoginState>(
        'nothing found anywhere: asks whether it was used before, and '
        'signs nothing yet',
        build: bloc,
        setUp: () => records(null),
        act: (bloc) => bloc.add(const LoginWithMetamask()),
        wait: const Duration(milliseconds: 200),
        verify: (bloc) {
          expect(bloc.state, isA<LoginAskUsedMetaMaskBefore>());
          expect(derivedFrom, isNull);
          neverSignedIn();
        },
      );

      blocTest<LoginBloc, LoginState>(
        'nothing found, No: the message signed twice alike, the marker posted '
        'by the auth key, then signed in with no password',
        build: bloc,
        setUp: () => records(null),
        act: (bloc) async {
          bloc.add(const LoginWithMetamask());
          await bloc.stream.firstWhere((s) => s is LoginAskUsedMetaMaskBefore);
          bloc.add(const AnswerUsedArDriveBefore(usedBefore: false));
        },
        wait: const Duration(milliseconds: 300),
        verify: (bloc) async {
          expect(bloc.state, isA<LoginSuccess>());
          final marker = posted().single;
          expect(tagsOf(marker), {
            'App-Name': 'ArDrive',
            'ArDrive-Account-Version': '2',
            'ArDrive-Account-Address': accountAddress,
          });
          expect(utf8.decode(marker.data), accountAddress);
          expect(marker.signatureConfig?.signatureType,
              SignatureConfig.ethereum.signatureType);
        },
      );

      blocTest<LoginBloc, LoginState>(
        'nothing found, No, with a MetaMask that signs differently each time: '
        'no account, no marker',
        build: bloc,
        setUp: () {
          records(null);
          when(() => ethereum.connect())
              .thenAnswer((_) async => _ChangingSigner(ethWallet));
        },
        act: (bloc) async {
          bloc.add(const LoginWithMetamask());
          await bloc.stream.firstWhere((s) => s is LoginAskUsedMetaMaskBefore);
          bloc.add(const AnswerUsedArDriveBefore(usedBefore: false));
        },
        wait: const Duration(milliseconds: 300),
        verify: (bloc) {
          expect(
              bloc.state,
              isA<LoginFailure>().having((s) => s.error, 'error',
                  isA<EthereumWalletSignsDifferently>()));
          neverSignedIn();
          verifyNever(() => turbo.postDataItem(
              dataItem: any(named: 'dataItem'), wallet: any(named: 'wallet')));
        },
      );

      blocTest<LoginBloc, LoginState>(
        'nothing found, No, and the marker can\'t be posted: nothing saved',
        build: bloc,
        setUp: () {
          records(null);
          when(() => turbo.postDataItem(
              dataItem: any(named: 'dataItem'),
              wallet: any(named: 'wallet'))).thenThrow(Exception('turbo down'));
        },
        act: (bloc) async {
          bloc.add(const LoginWithMetamask());
          await bloc.stream.firstWhere((s) => s is LoginAskUsedMetaMaskBefore);
          bloc.add(const AnswerUsedArDriveBefore(usedBefore: false));
        },
        wait: const Duration(milliseconds: 300),
        verify: (bloc) {
          expect(bloc.state, isA<LoginFailure>());
          neverSignedIn();
        },
      );

      Future<void> yesThenPassword(LoginBloc bloc) async {
        bloc.add(const LoginWithMetamask());
        await bloc.stream.firstWhere((s) => s is LoginAskUsedMetaMaskBefore);
        bloc.add(const AnswerUsedArDriveBefore(usedBefore: true));
        final asked = await bloc.stream.firstWhere((s) => s is PromptPassword)
            as PromptPassword;
        bloc.add(LoginWithPassword(
          password: 'their password',
          wallet: asked.wallet!,
          derivedEthWallet: asked.derivedEthWallet,
          showWalletCreated: false,
        ));
      }

      blocTest<LoginBloc, LoginState>(
        'nothing found, Yes: a password whose wallet has ArDrive history signs '
        'in, and its two verification records go up again',
        build: bloc,
        setUp: () => records(null),
        act: yesThenPassword,
        wait: const Duration(milliseconds: 500),
        verify: (bloc) {
          expect(bloc.state, isA<LoginSuccess>());
          final password = verify(() => auth.loginWithWallet(
              any(), any(), any(),
              sourceWalletAddress: any(named: 'sourceWalletAddress'),
              password: captureAny(named: 'password'),
              skipDriveCheck: any(named: 'skipDriveCheck'))).captured.single;
          expect(password, 'their password');
          final items = posted();
          expect(items, hasLength(2));
          expect(items.every((i) => tagsOf(i).isEmpty), isTrue,
              reason: 'version 1 records carry no tags');
          verifyNever(() => arweave.getFirstTxForWallet(any()));
        },
      );

      blocTest<LoginBloc, LoginState>(
        'nothing found, Yes: a password whose wallet has no history found no '
        'account, and nothing is posted or saved',
        build: bloc,
        setUp: () {
          records(null);
          when(() => auth.isExistingUser(any())).thenAnswer((_) async => false);
        },
        act: yesThenPassword,
        wait: const Duration(milliseconds: 500),
        verify: (bloc) {
          expect(
              bloc.state,
              isA<PromptPassword>()
                  .having((s) => s.noAccountFound, 'noAccountFound', isTrue));
          neverSignedIn();
          verifyNever(() => turbo.postDataItem(
              dataItem: any(named: 'dataItem'), wallet: any(named: 'wallet')));
        },
      );
    });
  });

  group('Welcome back', () {
    SavedAccount account(
      DeviceUnlockMethod method, {
      ProfileType type = ProfileType.arConnect,
      String? source,
    }) =>
        SavedAccount(
          address: user.walletAddress,
          profileType: type,
          unlockMethod: method,
          sourceWalletAddress: source,
          publicKey: 'public-key',
        );

    void saved(SavedAccount account) {
      when(() => auth.isUserLoggedIn()).thenAnswer((_) async => true);
      when(() => auth.savedAccount()).thenAnswer((_) async => account);
      when(() => auth.isBiometricsEnabled()).thenAnswer((_) async => true);
    }

    blocTest<LoginBloc, LoginState>(
      'an account its wallet opens asks for the wallet, never a password or '
      'biometrics, and calls no wallet at startup',
      build: bloc,
      setUp: () => saved(account(DeviceUnlockMethod.wander)),
      act: (bloc) => bloc.add(const CheckIfUserIsLoggedIn()),
      expect: () => [
        isA<LoginLoading>(),
        const PromptWalletUnlock(wallet: BrowserWallet.wander),
      ],
      verify: (_) {
        verifyNever(() => auth.unlockWithBiometrics(
            localizedReason: any(named: 'localizedReason')));
        verifyNever(() => arconnect.checkPermissions());
        verifyNever(() => arconnect.getWalletAddress());
      },
    );

    blocTest<LoginBloc, LoginState>(
      'a Wander profile saved before 3.0 opens with Wander, and says its '
      'drives lock again',
      build: bloc,
      setUp: () => saved(account(DeviceUnlockMethod.password)),
      act: (bloc) => bloc.add(const CheckIfUserIsLoggedIn()),
      expect: () => [
        isA<LoginLoading>(),
        const PromptWalletUnlock(wallet: BrowserWallet.wander, relocks: true),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'a password account still asks for its password',
      build: bloc,
      setUp: () {
        saved(account(DeviceUnlockMethod.password, type: ProfileType.json));
        when(() => auth.isBiometricsEnabled()).thenAnswer((_) async => false);
      },
      act: (bloc) => bloc.add(const CheckIfUserIsLoggedIn()),
      expect: () => [
        isA<LoginLoading>(),
        const PromptPassword(alreadyLoggedIn: true),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'Continue: Wander on this account, one approval, signed in',
      build: bloc,
      setUp: () {
        saved(account(DeviceUnlockMethod.wander));
        when(() => auth.unlockWithWallet(any())).thenAnswer((_) async => user);
      },
      act: (bloc) => bloc.add(const UnlockWithWallet()),
      expect: () => [
        const LoginWaitingOnWallet(
          wallet: BrowserWallet.wander,
          request: BrowserWalletRequest.openDrives,
        ),
        isA<LoginSuccess>(),
      ],
      verify: (_) {
        final source = verify(() => auth.unlockWithWallet(captureAny()))
            .captured
            .single as DeviceSecretSource;
        expect(source.method, DeviceUnlockMethod.wander);
      },
    );

    blocTest<LoginBloc, LoginState>(
      'Continue: Wander on another account opens nothing',
      build: bloc,
      setUp: () {
        saved(account(DeviceUnlockMethod.wander));
        when(() => arconnect.getWalletAddress())
            .thenAnswer((_) async => 'someone-else');
      },
      act: (bloc) => bloc.add(const UnlockWithWallet()),
      expect: () => [
        isA<LoginWaitingOnWallet>(),
        const PromptWalletUnlock(
          wallet: BrowserWallet.wander,
          problem: WalletUnlockProblem.otherAccount,
        ),
      ],
      verify: (_) => verifyNever(() => auth.unlockWithWallet(any())),
    );

    blocTest<LoginBloc, LoginState>(
      'Continue: a refusal stays on Welcome back and says so',
      build: bloc,
      setUp: () {
        saved(account(DeviceUnlockMethod.wander));
        when(() => auth.unlockWithWallet(any())).thenThrow(
            const DeviceUnlockRefusedException(DeviceUnlockStatus.declined));
      },
      act: (bloc) => bloc.add(const UnlockWithWallet()),
      expect: () => [
        isA<LoginWaitingOnWallet>(),
        const PromptWalletUnlock(
          wallet: BrowserWallet.wander,
          problem: WalletUnlockProblem.declined,
        ),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'Continue: a wallet that signs differently says so',
      build: bloc,
      setUp: () {
        saved(account(DeviceUnlockMethod.ethereum,
            type: ProfileType.json, source: ethWallet.credentials.address.hex));
        when(() => ethereum.connect()).thenAnswer((_) async => ethWallet);
        when(() => auth.unlockWithWallet(any())).thenThrow(
            const DeviceUnlockRefusedException(DeviceUnlockStatus.mismatch));
      },
      act: (bloc) => bloc.add(const UnlockWithWallet()),
      expect: () => [
        isA<LoginWaitingOnWallet>(),
        const PromptWalletUnlock(
          wallet: BrowserWallet.metamask,
          problem: WalletUnlockProblem.mismatch,
        ),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'Continue on a profile from before 3.0 makes a new one with the wallet',
      build: bloc,
      setUp: () => saved(account(DeviceUnlockMethod.password)),
      act: (bloc) => bloc.add(const UnlockWithWallet()),
      expect: () => [isA<LoginWaitingOnWallet>(), isA<LoginSuccess>()],
      verify: (_) {
        expect(capturedSource().method, DeviceUnlockMethod.wander);
        verifyNever(() => auth.unlockWithWallet(any()));
      },
    );

    blocTest<LoginBloc, LoginState>(
      'Continue on a Phantom profile from before 3.0 whose wallet derives '
      'another account: refused, and the saved profile is kept',
      build: bloc,
      setUp: () {
        when(() => auth.isUserLoggedIn()).thenAnswer((_) async => true);
        when(() => auth.savedAccount())
            .thenAnswer((_) async => const SavedAccount(
                  address: 'not-the-derived-account',
                  profileType: ProfileType.json,
                  unlockMethod: DeviceUnlockMethod.password,
                  sourceWalletAddress: 'So1Addr',
                  publicKey: 'public-key',
                ));
        when(() => solana.connect(provider: any(named: 'provider'))).thenAnswer(
            (_) async => const SolanaConnection(
                address: 'So1Addr', providerType: 'phantom'));
        when(() => solana.signMessage(any()))
            .thenAnswer((_) async => Uint8List.fromList(List.filled(64, 3)));
      },
      act: (bloc) => bloc.add(const UnlockWithWallet()),
      wait: const Duration(milliseconds: 300),
      expect: () => [
        isA<LoginWaitingOnWallet>(),
        isA<PromptWalletUnlock>().having(
            (s) => s.problem, 'problem', WalletUnlockProblem.notThisAccount),
      ],
      verify: (_) {
        verifyNever(() => auth.loginWithWallet(any(), any(), any(),
            sourceWalletAddress: any(named: 'sourceWalletAddress'),
            password: any(named: 'password'),
            skipDriveCheck: any(named: 'skipDriveCheck')));
        verifyNever(() => auth.logout());
      },
    );

    blocTest<LoginBloc, LoginState>(
      'Continue: saying no to connecting Phantom is a refusal, not another '
      'account',
      build: bloc,
      setUp: () {
        saved(account(DeviceUnlockMethod.solana,
            type: ProfileType.json, source: 'So1Addr'));
        when(() => solana.connect(provider: any(named: 'provider')))
            .thenAnswer((_) async => null);
      },
      act: (bloc) => bloc.add(const UnlockWithWallet()),
      expect: () => [
        isA<LoginWaitingOnWallet>(),
        isA<PromptWalletUnlock>()
            .having((s) => s.problem, 'problem', WalletUnlockProblem.declined),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'Continue on Phantom: no new wallet is made, the signature opens it',
      build: bloc,
      setUp: () {
        saved(account(DeviceUnlockMethod.solana,
            type: ProfileType.json, source: 'So1Addr'));
        when(() => solana.connect(provider: any(named: 'provider'))).thenAnswer(
            (_) async => const SolanaConnection(
                address: 'So1Addr', providerType: 'phantom'));
        when(() => solana.signMessage(any()))
            .thenAnswer((_) async => Uint8List.fromList(List.filled(64, 3)));
        when(() => auth.unlockWithWallet(any())).thenAnswer((_) async => user);
      },
      act: (bloc) => bloc.add(const UnlockWithWallet()),
      expect: () => [
        const LoginWaitingOnWallet(
          wallet: BrowserWallet.phantom,
          request: BrowserWalletRequest.openDrives,
        ),
        isA<LoginSuccess>(),
      ],
      verify: (_) => expect(derivedFrom, isNull),
    );

    blocTest<LoginBloc, LoginState>(
      'Cancel while the wallet is asked goes back to Welcome back',
      build: bloc,
      setUp: () {
        saved(account(DeviceUnlockMethod.wander));
        when(() => arconnect.checkPermissions())
            .thenAnswer((_) => Completer<bool>().future);
      },
      act: (bloc) async {
        bloc.add(const UnlockWithWallet());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const CancelWalletLogin());
      },
      expect: () => [
        isA<LoginWaitingOnWallet>(),
        const PromptWalletUnlock(wallet: BrowserWallet.wander),
      ],
      verify: (_) => verifyNever(() => auth.logout()),
    );
  });

  group('My files', () {
    late MemoryKeyValueStore store;

    LoginBloc withFirstDrive() => LoginBloc(
          arDriveAuth: auth,
          arConnectService: arconnect,
          ethereumProviderService: ethereum,
          solanaProviderService: solana,
          turboUploadService: turbo,
          arweaveService: arweave,
          downloadService: MockDownloadService(),
          userRepository: MockUserRepository(),
          profileCubit: MockProfileCubit(),
          configService: MockConfigService(),
          walletFromMnemonic: (_) async => wallet,
          firstDrive: FirstDrive(openStore: () async => store),
        );

    setUp(() {
      store = MemoryKeyValueStore();
      when(() => auth.isUserLoggedIn()).thenAnswer((_) async => true);
      when(() => auth.currentUser).thenReturn(user);
    });

    blocTest<LoginBloc, LoginState>(
      'an account ArDrive made gets My files at sign-up, as before',
      build: withFirstDrive,
      act: (bloc) async {
        bloc.add(const CreateNewWallet());
        await bloc.stream.firstWhere((s) => s is CreateNewPassword);
        bloc.add(FinishOnboarding(wallet: wallet));
        await bloc.stream.firstWhere((s) => s is LoginSuccess);
      },
      verify: (_) async => expect(
          await FirstDrive(openStore: () async => store)
              .claim(user.walletAddress),
          isTrue),
    );

    blocTest<LoginBloc, LoginState>(
      'a browser wallet sign-up gets none: My files waits for the first '
      'upload',
      build: withFirstDrive,
      act: (bloc) async {
        bloc.add(const AddWalletFromArConnect());
        await bloc.stream.firstWhere((s) => s is LoginSuccess);
      },
      verify: (_) async => expect(
          await FirstDrive(openStore: () async => store)
              .claim(user.walletAddress),
          isFalse),
    );
  });
}

/// A MetaMask whose signatures change every time, as a smart-contract or
/// MPC wallet's may.
class _ChangingSigner extends EthereumWallet {
  _ChangingSigner(this._inner);

  final EthereumProviderWallet _inner;
  var _n = 0;

  @override
  Future<Uint8List> sign(Uint8List message, [String? context]) async {
    final signature = await _inner.sign(message);
    signature[64] ^= ++_n;
    return signature;
  }

  @override
  Future<String> getAddress() => _inner.getAddress();

  @override
  Future<String> getOwner() => _inner.getOwner();

  @override
  SignatureConfig getSignatureConfig() => SignatureConfig.ethereum;

  @override
  Map<String, dynamic> toJwk() => throw UnimplementedError();
}
