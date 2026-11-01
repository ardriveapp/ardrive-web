import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/permanence/permanence_cache.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/components/icon_theme_switcher.dart';
import 'package:ardrive/theme/theme_switcher_bloc.dart';
import 'package:ardrive/theme/theme_switcher_state.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../test_utils/utils.dart';

class _MockPaymentService extends Mock implements PaymentService {}

class _MockProfileNameBloc extends MockBloc<ProfileNameEvent, ProfileNameState>
    implements ProfileNameBloc {}

class _MockThemeBloc extends MockBloc<ThemeSwitcherEvent, ThemeSwitcherState>
    implements ThemeSwitcherBloc {}

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

/// The slim profile panel: the address with copy, credits, Account and
/// security, Settings, Help and Log out. The wallet rows and Forget all
/// moved to Account and security.
void main() {
  var balance = BigInt.zero;
  late AppRouterDelegate router;
  // Full length: the card truncates it, and a short one throws.
  const walletAddress = 'Aa1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8S9t0Uv';
  final user = User(
    password: 'password',
    wallet: getTestWallet(),
    walletAddress: walletAddress,
    walletBalance: BigInt.zero,
    cipherKey: SecretKey([1, 2, 3]),
    profileType: ProfileType.json,
    errorFetchingIOTokens: false,
  );

  late Database db;
  late MockProfileCubit profileCubit;
  late MockArDriveAuth auth;

  setUpAll(() {
    registerFallbackValue(getTestWallet());
  });

  setUp(() {
    db = getTestDb();
    balance = BigInt.zero;
    router = AppRouterDelegate();

    profileCubit = MockProfileCubit();
    whenListen(
      profileCubit,
      const Stream<ProfileState>.empty(),
      initialState: ProfileLoggedIn(user: user, useTurbo: false),
    );

    auth = MockArDriveAuth();
    when(() => auth.currentUser).thenReturn(user);
  });

  tearDown(() => db.close());

  Future<void> pumpCard(WidgetTester tester, {PermanenceCache? cache}) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final config = MockConfigService();
    when(() => config.config).thenReturn(
      AppConfig(allowedDataItemSizeForTurbo: 0, stripePublishableKey: ''),
    );

    final payments = _MockPaymentService();
    when(() => payments.getBalance(wallet: any(named: 'wallet')))
        .thenAnswer((_) async => balance);
    when(() => auth.onAuthStateChanged())
        .thenAnswer((_) => const Stream.empty());
    when(() => auth.refreshBalance()).thenAnswer((_) async {});

    final names = _MockProfileNameBloc();
    whenListen(
      names,
      const Stream<ProfileNameState>.empty(),
      initialState: const ProfileNameInitial(walletAddress),
    );

    final themeBloc = _MockThemeBloc();
    whenListen(
      themeBloc,
      const Stream<ThemeSwitcherState>.empty(),
      initialState: ThemeSwitcherLightTheme(),
    );

    final preferences = _MockUserPreferencesRepository();
    when(() => preferences.watch()).thenAnswer((_) => const Stream.empty());
    when(() => preferences.currentPreferences).thenReturn(null);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<DriveDao>.value(value: db.driveDao),
          RepositoryProvider<ArDriveAuth>.value(value: auth),
          RepositoryProvider<ConfigService>.value(value: config),
          RepositoryProvider<PaymentService>.value(value: payments),
          RepositoryProvider<ArweaveService>.value(
            value: MockArweaveService(),
          ),
          RepositoryProvider<UserPreferencesRepository>.value(
            value: preferences,
          ),
          RepositoryProvider<PermanenceCache>.value(
            value: cache ?? PermanenceCache(),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: profileCubit),
            BlocProvider<ProfileNameBloc>.value(value: names),
            BlocProvider<ThemeSwitcherBloc>.value(value: themeBloc),
            ListenableProvider<AppRouterDelegate>.value(
              value: router,
            ),
            // Read by the dialog the permanence link opens.
            ChangeNotifierProvider<ActivityTracker>(
              create: (_) => ActivityTracker(),
            ),
          ],
          child: ArDriveApp(
            builder: (context) => const MaterialApp(
              localizationsDelegates: [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: [Locale('en', '')],
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topRight,
                  child: ProfileCard(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Pumps on the real clock until [finder] finds something, for work the
  /// database does off the test's fake one.
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 50 && finder.evaluate().isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }
  }

  /// Unmounts on the real clock, so the card's database watch is cancelled
  /// there: cancelled on the fake one, it leaves a timer behind that holds up
  /// closing the database.
  Future<void> takeDown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  Future<void> openCard(WidgetTester tester) async {
    await tester.tap(find.byType(ProfileCardHeader));
    await tester.pump();
  }

  testWidgets('no credits: Add credits, and no Wallet section', (tester) async {
    await tester.runAsync(() async {
      await pumpCard(tester);
      await openCard(tester);
      await waitFor(tester, find.byKey(const Key('profileAddCredits')));

      expect(find.byKey(const Key('profileAddCredits')), findsOneWidget);
      expect(find.text('Add credits'), findsOneWidget);
      expect(find.byKey(const Key('profileCreditsBalance')), findsNothing);

      expect(find.text('Account and security'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Help'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);

      expect(find.text('Wallet'), findsNothing);
      expect(find.text('Wallets'), findsNothing);
      expect(find.text('AR'), findsNothing);
      expect(find.text('ArNS wallet'), findsNothing);
      expect(find.text('Link a Solana wallet'), findsNothing);
      expect(find.text('Download wallet backup'), findsNothing);
      expect(find.text('Forget all on this device'), findsNothing);

      await takeDown(tester);
    });
  });

  testWidgets('credits: the balance, with its add button', (tester) async {
    balance = BigInt.from(1500000000000);
    await tester.runAsync(() async {
      await pumpCard(tester);
      await openCard(tester);
      await waitFor(tester, find.text('1.5000'));

      expect(find.text('1.5000'), findsOneWidget);
      expect(find.byKey(const Key('profileAddCredits')), findsNothing);
      expect(find.bySemanticsLabel('Add credits'), findsOneWidget);

      await takeDown(tester);
    });
  });

  testWidgets('the add button is at least 40 square to press', (tester) async {
    balance = BigInt.from(1500000000000);
    await tester.runAsync(() async {
      await pumpCard(tester);
      await openCard(tester);
      await waitFor(tester, find.text('1.5000'));

      final press = find
          .ancestor(
            of: find.byIcon(Icons.add),
            matching: find.byType(GestureDetector),
          )
          .first;
      final size = tester.getSize(press);
      expect(size.width, greaterThanOrEqualTo(40));
      expect(size.height, greaterThanOrEqualTo(40));

      await takeDown(tester);
    });
  });

  testWidgets('the address has a named copy button', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.runAsync(() async {
      await pumpCard(tester);
      await openCard(tester);
      await waitFor(tester, find.byKey(const Key('profileCopyAddress')));

      expect(find.bySemanticsLabel('Copy address'), findsOneWidget);

      await takeDown(tester);
    });
    semantics.dispose();
  });

  testWidgets('copy takes the address shown: a Phantom account\'s Solana one',
      (tester) async {
    const solana = '7xKpQd2aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567Qd2a';
    final phantomUser = user.copyWith(sourceWalletAddress: solana);
    whenListen(
      profileCubit,
      const Stream<ProfileState>.empty(),
      initialState: ProfileLoggedIn(user: phantomUser, useTurbo: false),
    );
    when(() => auth.currentUser).thenReturn(phantomUser);

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

    await tester.runAsync(() async {
      await pumpCard(tester);
      await openCard(tester);
      await waitFor(tester, find.byKey(const Key('profileCopyAddress')));

      // The whole 40 px square takes the tap, not only the icon.
      final button = find.byKey(const Key('profileCopyAddress'));
      expect(tester.getSize(button), const Size(40, 40));
      await tester.tapAt(tester.getTopLeft(button) + const Offset(2, 2));
      await tester.pump();

      expect(copied, solana);

      await takeDown(tester);
    });
  });

  testWidgets('Account and security opens the page and closes the panel',
      (tester) async {
    await tester.runAsync(() async {
      await pumpCard(tester);
      await openCard(tester);
      await waitFor(tester, find.text('Account and security'));

      await tester.tap(find.text('Account and security'));
      // The overlay hides on the frame after it is asked to.
      await tester.pump();
      await tester.pump();

      expect(router.showingAccount, isTrue);
      expect(find.text('Account and security'), findsNothing);

      await takeDown(tester);
    });
  });

  testWidgets('Billing sits under Account and security and opens the page',
      (tester) async {
    await tester.runAsync(() async {
      await pumpCard(tester);
      await openCard(tester);
      await waitFor(tester, find.byKey(const Key('profileBilling')));

      final account = tester.getTopLeft(
        find.byKey(const Key('profileAccountAndSecurity')),
      );
      final billing =
          tester.getTopLeft(find.byKey(const Key('profileBilling')));
      expect(billing.dy, greaterThan(account.dy));

      await tester.tap(find.byKey(const Key('profileBilling')));
      await tester.pump();
      await tester.pump();

      expect(router.showingBilling, isTrue);
      expect(router.showingAccount, isFalse);
      expect(find.byKey(const Key('profileBilling')), findsNothing);

      await takeDown(tester);
    });
  });

  testWidgets(
      'Settings sits under Billing, opens the page, and keeps the theme toggle',
      (tester) async {
    await tester.runAsync(() async {
      await pumpCard(tester);
      await openCard(tester);
      await waitFor(tester, find.byKey(const Key('profileSettings')));

      final billing =
          tester.getTopLeft(find.byKey(const Key('profileBilling')));
      final settings =
          tester.getTopLeft(find.byKey(const Key('profileSettings')));
      expect(settings.dy, greaterThan(billing.dy));

      // The old accordion is gone; the quick theme switch stays.
      expect(find.text('Switch gateway'), findsNothing);
      expect(find.text('Automatic sync'), findsNothing);
      expect(find.byType(ArDriveAccordion), findsNothing);
      expect(find.byType(IconThemeSwitcher), findsOneWidget);

      await tester.tap(find.byKey(const Key('profileSettings')));
      await tester.pump();
      await tester.pump();

      expect(router.showingSettings, isTrue);
      expect(find.byKey(const Key('profileSettings')), findsNothing);

      await takeDown(tester);
    });
  });
}
