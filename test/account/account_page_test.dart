import 'package:ardrive/account/presentation/account_page.dart';
import 'package:ardrive/arns/data/arns_wallet_store.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/device_unlock/data/device_tabs.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/app_route_information_parser.dart';
import 'package:ardrive/pages/app_route_path.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/user/download_wallet/download_wallet_modal.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/io_utils.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../test_utils/utils.dart';

class _MockIOUtils extends Mock implements ArDriveIOUtils {}

class _MockDeviceTabs extends Mock implements DeviceTabs {}

class _MockWalletCubit extends MockCubit<ArNSWalletState>
    implements ArNSWalletCubit {}

const _arweave = 'Aa1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8S9t0Uv';
const _solana = '7xKpQd2aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567Qd2a';
const _linkedSolana = 'CBsEKdomKa9nwF4fMiV5iFerfQPT73Et2ZKWpdCLHHsv';
const _ethereum = '0x4f2a00000000000000000000000000000000091bc';

User _user({
  ProfileType type = ProfileType.json,
  String? source,
}) =>
    User(
      password: 'password',
      wallet: getTestWallet(),
      walletAddress: _arweave,
      walletBalance: BigInt.zero,
      cipherKey: SecretKey([1, 2, 3]),
      profileType: type,
      errorFetchingIOTokens: false,
      sourceWalletAddress: source,
    );

/// Account and security, for each way of signing in.
void main() {
  late MockArDriveAuth auth;
  late MockDriveDao driveDao;
  late MockProfileCubit profileCubit;
  late AppRouterDelegate router;
  late _MockIOUtils ioUtils;
  late _MockDeviceTabs tabs;
  late _MockWalletCubit walletCubit;

  setUpAll(() {
    registerFallbackValue(SecretKey([0]));
  });

  setUp(() {
    auth = MockArDriveAuth();
    driveDao = MockDriveDao();
    profileCubit = MockProfileCubit();
    router = AppRouterDelegate();
    ioUtils = _MockIOUtils();
    tabs = _MockDeviceTabs();
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required User user,
    int remembered = 2,
    bool namesOn = true,
    ArNSWalletState? wallet,
    String? solanaProvider,
    bool metaMask = false,
    Size size = const Size(390, 900),
    bool dark = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    when(() => auth.currentUser).thenReturn(user);
    whenListen(
      profileCubit,
      const Stream<ProfileState>.empty(),
      initialState: ProfileLoggedIn(user: user, useTurbo: false),
    );
    when(() => driveDao.watchRememberedDriveKeyCount(
          ownerAddress: any(named: 'ownerAddress'),
        )).thenAnswer((_) => Stream.value(remembered));

    final config = MockConfigService();
    when(() => config.config).thenReturn(AppConfig(
      allowedDataItemSizeForTurbo: 0,
      stripePublishableKey: '',
      enableArNS: namesOn,
    ));

    walletCubit = _MockWalletCubit();
    whenListen(
      walletCubit,
      const Stream<ArNSWalletState>.empty(),
      initialState: wallet ??
          const ArNSWalletState(enabled: true, profileAddress: _arweave),
    );
    when(() => walletCubit.unlink()).thenAnswer((_) async {});

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ArDriveAuth>.value(value: auth),
          RepositoryProvider<DriveDao>.value(value: driveDao),
          RepositoryProvider<ConfigService>.value(value: config),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: profileCubit),
            BlocProvider<ArNSWalletCubit>.value(value: walletCubit),
            ListenableProvider<AppRouterDelegate>.value(value: router),
            // Read by the dialogs the rows open.
            ChangeNotifierProvider<ActivityTracker>(
              create: (_) => ActivityTracker(),
            ),
          ],
          child: ArDriveApp(
            themeData: dark ? null : lightTheme(),
            builder: (context) => MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: const [Locale('en', '')],
              theme: ArDriveTheme.of(context).themeData.materialThemeData,
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: AccountSections(
                    solanaProvider: solanaProvider,
                    ioUtils: ioUtils,
                    tabs: tabs,
                    metaMask: metaMask,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('sign in', () {
    testWidgets('a keyfile, phrase or generated account downloads its keyfile',
        (tester) async {
      await pumpPage(tester, user: _user());

      expect(find.text('Keyfile'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Connected'), findsNothing);
    });

    testWidgets('Download asks for the password before anything downloads',
        (tester) async {
      await pumpPage(tester, user: _user());

      await tester.tap(find.byKey(const Key('accountKeyfileDownload')));
      await tester.pumpAndSettle();

      expect(find.byType(DownloadWalletModal), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);
      verifyNever(() => auth.unlockUser(password: any(named: 'password')));
      verifyZeroInteractions(ioUtils);
    });

    testWidgets('Wander keeps the key', (tester) async {
      await pumpPage(tester, user: _user(type: ProfileType.arConnect));

      expect(find.text('Wander'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
      expect(
        find.text('Wander keeps your key. Back it up there.'),
        findsOneWidget,
      );
      expect(find.text('Keyfile'), findsNothing);
      expect(find.text('Download'), findsNothing);
    });

    testWidgets('Phantom, by name', (tester) async {
      await pumpPage(
        tester,
        user: _user(source: _solana),
        solanaProvider: 'phantom',
      );

      expect(find.text('Phantom'), findsOneWidget);
      expect(
        find.text('Phantom signs you in. Your files stay with this wallet.'),
        findsOneWidget,
      );
      expect(find.text('Download'), findsNothing);
    });

    testWidgets('Solflare, by name; an unknown Solana wallet, generically',
        (tester) async {
      await pumpPage(
        tester,
        user: _user(source: _solana),
        solanaProvider: 'solflare',
      );
      expect(find.text('Solflare'), findsOneWidget);

      await pumpPage(tester, user: _user(source: _solana));
      expect(find.text('Solana wallet'), findsOneWidget);
    });

    testWidgets('MetaMask, when MetaMask is there', (tester) async {
      await pumpPage(tester, user: _user(source: _ethereum), metaMask: true);

      expect(find.text('MetaMask'), findsOneWidget);
      expect(
        find.text('MetaMask signs you in. Your files stay with this wallet.'),
        findsOneWidget,
      );
      expect(find.text('Download'), findsNothing);
    });
  });

  testWidgets('another Ethereum wallet is not called MetaMask', (tester) async {
    await pumpPage(tester, user: _user(source: _ethereum));

    expect(find.text('MetaMask'), findsNothing);
    expect(find.text('Ethereum wallet'), findsOneWidget);
    expect(
      find.text(
          'Ethereum wallet signs you in. Your files stay with this wallet.'),
      findsOneWidget,
    );
  });

  group('this device', () {
    testWidgets('says how many drives it remembers, and Forget asks first',
        (tester) async {
      when(() => driveDao.rememberedDriveIds(
            ownerAddress: any(named: 'ownerAddress'),
          )).thenAnswer((_) async => ['a', 'b']);
      when(() => driveDao.forgetAllDriveKeys(
            any(),
            ownerAddress: any(named: 'ownerAddress'),
          )).thenAnswer((_) async => 2);

      await pumpPage(tester, user: _user(), remembered: 2);
      expect(find.text('2 drives remembered'), findsOneWidget);

      await tester.tap(find.byKey(const Key('accountForgetDrives')));
      await tester.pumpAndSettle();
      expect(find.byType(ForgetAllOnThisDeviceDialog), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      verifyNever(() => driveDao.forgetAllDriveKeys(
            any(),
            ownerAddress: any(named: 'ownerAddress'),
          ));
      verifyNever(() => tabs.announceForgotten(any()));

      await tester.tap(find.byKey(const Key('accountForgetDrives')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forget').last);
      await tester.pumpAndSettle();
      verify(() => driveDao.forgetAllDriveKeys(
            any(),
            ownerAddress: _arweave,
          )).called(1);
      // The other tabs are told which drives went.
      verify(() => tabs.announceForgotten(['a', 'b'])).called(1);
    });

    testWidgets('one drive is one drive', (tester) async {
      await pumpPage(tester, user: _user(), remembered: 1);
      expect(find.text('1 drive remembered'), findsOneWidget);
    });

    testWidgets('none remembered: says so, and offers nothing', (tester) async {
      await pumpPage(tester, user: _user(), remembered: 0);

      expect(find.text('No drives remembered'), findsOneWidget);
      expect(find.byKey(const Key('accountForgetDrives')), findsNothing);
    });
  });

  group('addresses', () {
    testWidgets('an Arweave account: its address, then Link for names',
        (tester) async {
      await pumpPage(tester, user: _user());

      expect(find.text('Arweave, for your files'), findsOneWidget);
      expect(find.text('Aa1b2C...t0Uv'), findsOneWidget);
      expect(find.text('Solana, for names'), findsOneWidget);
      expect(find.byKey(const Key('accountNamesLink')), findsOneWidget);
      expect(find.text('Ethereum, for sign-in'), findsNothing);
    });

    testWidgets('a linked names wallet: its address, copy and Unlink',
        (tester) async {
      await pumpPage(
        tester,
        user: _user(type: ProfileType.arConnect),
        wallet: const ArNSWalletState(
          enabled: true,
          profileAddress: _arweave,
          linked: LinkedArNSWallet(address: _linkedSolana),
        ),
      );

      expect(find.byKey(const Key('accountNamesLink')), findsNothing);
      expect(find.text('CBsEKd...HHsv'), findsOneWidget);
      expect(find.byKey(const Key('accountNamesUnlink')), findsOneWidget);
      expect(find.bySemanticsLabel('Copy Solana address'), findsOneWidget);

      await tester.tap(find.byKey(const Key('accountNamesUnlink')));
      await tester.pump();
      verify(() => walletCubit.unlink()).called(1);
    });

    testWidgets('names off: no names row', (tester) async {
      await pumpPage(tester, user: _user(), namesOn: false);
      expect(find.text('Solana, for names'), findsNothing);
    });

    testWidgets('Phantom: its Solana address is the names wallet, no Link',
        (tester) async {
      await pumpPage(
        tester,
        user: _user(source: _solana),
        solanaProvider: 'phantom',
        wallet: const ArNSWalletState(
          enabled: true,
          profileAddress: _arweave,
          linked: LinkedArNSWallet(address: _solana),
        ),
      );

      expect(find.text('Solana, for sign-in and names'), findsOneWidget);
      expect(find.text('Arweave, for your files'), findsOneWidget);
      expect(find.text('Solana, for names'), findsNothing);
      expect(find.byKey(const Key('accountNamesLink')), findsNothing);
    });

    testWidgets(
        'Phantom with another names wallet linked: that wallet, with Unlink',
        (tester) async {
      await pumpPage(
        tester,
        user: _user(source: _solana),
        solanaProvider: 'phantom',
        wallet: const ArNSWalletState(
          enabled: true,
          profileAddress: _arweave,
          linked: LinkedArNSWallet(address: _linkedSolana),
        ),
      );

      expect(find.text('Solana, for sign-in'), findsOneWidget);
      expect(find.text('Solana, for sign-in and names'), findsNothing);
      expect(find.text('7xKpQd...Qd2a'), findsOneWidget);
      expect(find.text('Solana, for names'), findsOneWidget);
      expect(find.text('CBsEKd...HHsv'), findsOneWidget);
      expect(find.byKey(const Key('accountNamesUnlink')), findsOneWidget);

      await tester.tap(find.byKey(const Key('accountNamesUnlink')));
      await tester.pump();
      verify(() => walletCubit.unlink()).called(1);
    });

    testWidgets('Phantom with no names wallet linked: Link to get one back',
        (tester) async {
      await pumpPage(
        tester,
        user: _user(source: _solana),
        solanaProvider: 'phantom',
      );

      expect(find.text('Solana, for sign-in'), findsOneWidget);
      expect(find.byKey(const Key('accountNamesLink')), findsOneWidget);
    });

    testWidgets('MetaMask: Ethereum, Arweave, then Link for names',
        (tester) async {
      await pumpPage(tester, user: _user(source: _ethereum));

      expect(find.text('Ethereum, for sign-in'), findsOneWidget);
      expect(find.text('Arweave, for your files'), findsOneWidget);
      expect(find.byKey(const Key('accountNamesLink')), findsOneWidget);
    });

    testWidgets('copy puts the whole address on the clipboard and says so',
        (tester) async {
      final semantics = tester.ensureSemantics();
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await pumpPage(tester, user: _user());
      await tester.tap(find.bySemanticsLabel('Copy Arweave address'));
      await tester.pump();

      expect(copied, _arweave);
      expect(find.text('Copied!'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      semantics.dispose();
    });
  });

  group('route', () {
    test('/account parses to the page and back', () async {
      final parser = AppRouteInformationParser();
      final path = await parser.parseRouteInformation(
        RouteInformation(uri: Uri.parse('/account')),
      );
      expect(path.account, isTrue);
      expect(
        parser.restoreRouteInformation(AppRoutePath.account()).uri.path,
        '/account',
      );
    });

    test('back returns to what the page covered', () {
      final router = AppRouterDelegate()..showNames();
      router.showAccount();
      expect(router.showingAccount, isTrue);
      expect(router.showingNames, isFalse);
      expect(router.currentConfiguration.account, isTrue);

      router.closeAccount();
      expect(router.showingAccount, isFalse);
      expect(router.showingNames, isTrue);
    });

    test('back from an opened address lands on the drives list', () async {
      final router = AppRouterDelegate();
      await router.setNewRoutePath(AppRoutePath.account());
      expect(router.showingAccount, isTrue);

      router.closeAccount();
      expect(router.showingAccount, isFalse);
      expect(router.showingDrivesList, isTrue);
    });

    test('is shown only to somebody signed in', () {
      final router = AppRouterDelegate()..showAccount();
      expect(
        router.showsAccount(ProfileLoggedIn(user: _user(), useTurbo: false)),
        isTrue,
      );
      for (final state in [
        ProfilePromptAdd(),
        ProfilePromptLogIn(),
        ProfileCheckingAvailability(),
      ]) {
        expect(router.showsAccount(state), isFalse, reason: '$state');
      }
      expect(
        AppRouterDelegate().showsAccount(
          ProfileLoggedIn(user: _user(), useTurbo: false),
        ),
        isFalse,
      );
    });

    test('a link to it is honoured after sign-in', () async {
      final router = AppRouterDelegate();
      await router.setNewRoutePath(AppRoutePath.account());
      router.signingIn = true;

      router.landAfterSignIn();

      expect(router.signingIn, isFalse);
      expect(router.showingAccount, isTrue);
      expect(router.showingDrivesList, isFalse);
      expect(router.currentConfiguration.account, isTrue);

      // With no link, sign-in lands on the drives list.
      final plain = AppRouterDelegate()..signingIn = true;
      plain.landAfterSignIn();
      expect(plain.showingDrivesList, isTrue);
    });

    test('opening a drive or another page leaves it', () {
      final router = AppRouterDelegate()..showAccount();
      router.openDriveFromList('d1');
      expect(router.showingAccount, isFalse);

      router
        ..showAccount()
        ..showWebPages();
      expect(router.showingAccount, isFalse);
    });
  });
}
