import 'dart:async';
import 'dart:convert';

import 'package:ardrive/billing/data/billing_session_cache.dart';
import 'package:ardrive/billing/data/purchase.dart';
import 'package:ardrive/billing/presentation/billing_sections.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/pages/app_route_information_parser.dart';
import 'package:ardrive/pages/app_route_path.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/turbo/models/turbo_free_allowance.dart';
import 'package:ardrive/turbo/services/credit_sharing_service.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

class _MockPaymentService extends Mock implements PaymentService {}

class _FakeSharing extends CreditSharingService {
  _FakeSharing({this.fails = false});

  final bool fails;
  final shared = <({String from, String to, BigInt winc})>[];

  @override
  bool get isSupported => true;

  @override
  Future<void> shareCreditsFromSignInWallet({
    required String sourceAddress,
    required String approvedAddress,
    required BigInt approvedWinc,
  }) async {
    if (fails) throw StateError('refused');
    shared.add((from: sourceAddress, to: approvedAddress, winc: approvedWinc));
  }
}

const _arweave = 'Aa1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8S9t0Uv';
const _solana = '7xKpQd2aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567Qd2a';
const _ethereum = '0x4f2a00000000000000000000000000000000091bc';
final _credit = BigInt.from(10).pow(12);

User _user({
  ProfileType type = ProfileType.json,
  String? source,
  BigInt? ar,
  String address = _arweave,
}) =>
    User(
      password: 'password',
      wallet: getTestWallet(),
      walletAddress: address,
      walletBalance: ar ?? BigInt.zero,
      cipherKey: SecretKey([1, 2, 3]),
      profileType: type,
      errorFetchingIOTokens: false,
      sourceWalletAddress: source,
    );

Map<String, dynamic> _card(String date, int cents, int credits,
        {String currency = 'usd', String? gift}) =>
    {
      'type': 'fiat',
      'date': date,
      'wincCredited': '${credits * 1000000000000}',
      'paymentAmount': cents,
      'currencyType': currency,
      'paymentProvider': 'stripe',
      'receiptId': 'pi_3QabcdefghijkX9',
      if (gift != null) 'giftMessage': gift,
    };

Map<String, dynamic> _crypto(String date) => {
      'type': 'crypto',
      'date': date,
      'wincCredited': '2200000000000',
      'tokenType': 'arweave',
      'tokenQuantity': '2500000000000',
      'usdEquivalent': 18.0,
      'senderAddress': 'x',
      'transactionId': 'Hm3rAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAtW8c',
      'blockHeight': 1,
    };

TurboPaymentsPage _page(List<Map<String, dynamic>> rows,
        {bool more = false, String? cursor}) =>
    TurboPaymentsPage(payments: rows, hasMore: more, cursor: cursor);

TurboBalanceDetails _details({
  int own = 10,
  int effective = 10,
  List<TurboCreditApproval> given = const [],
  List<TurboCreditApproval> received = const [],
}) =>
    TurboBalanceDetails(
      effective: BigInt.from(effective) * _credit,
      controlled: BigInt.from(own) * _credit,
      given: given,
      received: received,
    );

void main() {
  late _MockPaymentService payments;
  late MockProfileCubit profileCubit;
  late BillingSessionCache cache;
  late List<(String, String)> saved;

  setUpAll(() {
    registerFallbackValue(getTestWallet());
    registerFallbackValue(WalletType.solana);
  });

  setUp(() {
    payments = _MockPaymentService();
    profileCubit = MockProfileCubit();
    cache = BillingSessionCache();
    saved = [];
    when(() => payments.getBalanceDetails(wallet: any(named: 'wallet')))
        .thenAnswer((_) async => _details());
    when(() => payments.getPriceForBytes(byteSize: any(named: 'byteSize')))
        .thenAnswer((_) async => _credit * BigInt.from(5));
    when(() => payments.getFreeAllowance(wallet: any(named: 'wallet')))
        .thenAnswer((_) async => TurboFreeAllowance.bytes(1000));
    when(() => payments.getPaymentHistoryPage(
          wallet: any(named: 'wallet'),
          cursor: any(named: 'cursor'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async => _page([]));
    when(() => payments.getBalanceForAddress(
          address: any(named: 'address'),
          walletType: any(named: 'walletType'),
        )).thenAnswer((_) async => BigInt.zero);
  });

  void historyIs(List<TurboPaymentsPage> pages) {
    var i = 0;
    when(() => payments.getPaymentHistoryPage(
          wallet: any(named: 'wallet'),
          cursor: any(named: 'cursor'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async => pages[i < pages.length ? i++ : i - 1]);
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    required User user,
    String? solanaProvider,
    bool metaMask = false,
    CreditSharingService? sharing,
    Size size = const Size(390, 1600),
    bool dark = false,
    bool saveThrows = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    whenListen(
      profileCubit,
      const Stream<ProfileState>.empty(),
      initialState: ProfileLoggedIn(user: user, useTurbo: false),
    );
    final config = MockConfigService();
    when(() => config.config).thenReturn(AppConfig(
      allowedDataItemSizeForTurbo: 0,
      stripePublishableKey: '',
    ));

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<PaymentService>.value(value: payments),
          RepositoryProvider<BillingSessionCache>.value(value: cache),
          RepositoryProvider<ConfigService>.value(value: config),
        ],
        child: BlocProvider<ProfileCubit>.value(
          value: profileCubit,
          child: ArDriveApp(
            themeData: dark ? null : lightTheme(),
            builder: (context) => MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: const [Locale('en', '')],
              theme: ArDriveTheme.of(context).themeData.materialThemeData,
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: BillingSections(
                    solanaProvider: solanaProvider,
                    metaMask: metaMask,
                    creditSharing: sharing ?? _FakeSharing(),
                    saveCsv: (name, bytes) async {
                      if (saveThrows) throw StateError('no');
                      saved.add((name, utf8.decode(bytes)));
                    },
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

  int historyCalls() => verify(() => payments.getPaymentHistoryPage(
        wallet: any(named: 'wallet'),
        cursor: any(named: 'cursor'),
        limit: any(named: 'limit'),
      )).callCount;

  group('balance card', () {
    testWidgets('shows credits, storage, the split and the free line',
        (tester) async {
      when(() => payments.getBalanceDetails(wallet: any(named: 'wallet')))
          .thenAnswer((_) async => _details(own: 10, effective: 12));
      await pumpPage(tester, user: _user());

      expect(find.text('12.0000'), findsOneWidget);
      expect(find.byKey(const Key('billingStorage')), findsOneWidget);
      expect(find.text('About 2.4 GB of storage'), findsOneWidget);
      expect(
          find.text('10.0000 yours · 2.0000 shared with you'), findsOneWidget);
      expect(
        find.text(
            'Small uploads are free while your free upload allowance lasts.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('billingAddCredits')), findsOneWidget);
    });

    testWidgets('no split line when nothing is shared with you',
        (tester) async {
      await pumpPage(tester, user: _user());
      expect(find.byKey(const Key('billingYoursAndShared')), findsNothing);
    });

    testWidgets('says the allowance is used up only when Turbo says 0',
        (tester) async {
      when(() => payments.getFreeAllowance(wallet: any(named: 'wallet')))
          .thenAnswer((_) async => TurboFreeAllowance.bytes(0));
      await pumpPage(tester, user: _user());
      expect(find.text('Free upload allowance used up'), findsOneWidget);
      expect(find.byKey(const Key('billingFreeAllowance')), findsNothing);
    });

    testWidgets('an unknown allowance shows no line', (tester) async {
      when(() => payments.getFreeAllowance(wallet: any(named: 'wallet')))
          .thenThrow(Exception('down'));
      await pumpPage(tester, user: _user());
      expect(find.byKey(const Key('billingFreeAllowance')), findsNothing);
      expect(find.byKey(const Key('billingFreeAllowanceUsed')), findsNothing);
    });

    testWidgets('a failed balance read says so, never 0, and Try again reads',
        (tester) async {
      var fail = true;
      when(() => payments.getBalanceDetails(wallet: any(named: 'wallet')))
          .thenAnswer((_) async {
        if (fail) throw Exception('down');
        return _details(own: 3, effective: 3);
      });
      await pumpPage(tester, user: _user());

      expect(find.text("Couldn't load your balance"), findsOneWidget);
      expect(find.byKey(const Key('billingBalanceFigure')), findsNothing);
      expect(find.text('0.0000'), findsNothing);

      fail = false;
      await tester.tap(find.byKey(const Key('billingBalanceRetry')));
      await tester.pumpAndSettle();
      expect(find.text('3.0000'), findsOneWidget);
      expect(find.text("Couldn't load your balance"), findsNothing);
    });

    testWidgets('an account Turbo has never seen has 0 credits, not an error',
        (tester) async {
      when(() => payments.getBalanceDetails(wallet: any(named: 'wallet')))
          .thenThrow(TurboUserNotFound());
      await pumpPage(tester, user: _user());
      expect(find.text('0.0000'), findsOneWidget);
      expect(find.text("Couldn't load your balance"), findsNothing);
      expect(find.byKey(const Key('billingStorage')), findsNothing);
    });
  });

  group('keyfile account', () {
    testWidgets('shows the AR row and loads purchases by itself',
        (tester) async {
      historyIs([
        _page([
          _card('2026-10-12T10:00:00.000Z', 2500, 3, gift: 'Enjoy'),
          _crypto('2026-09-03T10:00:00.000Z'),
          _card('2026-08-01T10:00:00.000Z', 0, 10, currency: 'winc'),
        ]),
      ]);
      await pumpPage(
        tester,
        user: _user(ar: BigInt.from(840000000000)),
      );

      expect(find.byKey(const Key('billingArRow')), findsOneWidget);
      expect(find.text('AR, for paying uploads directly'), findsOneWidget);
      expect(find.text('0.8400 AR'), findsOneWidget);

      expect(historyCalls(), 1);
      expect(find.byKey(const Key('billingShowPurchases')), findsNothing);
      expect(find.text('Card'), findsNWidgets(2));
      expect(find.text('\$25.00'), findsOneWidget);
      expect(find.text('Crypto'), findsOneWidget);
      expect(find.text('2.5 AR'), findsOneWidget);
      expect(find.text('~\$18.00'), findsOneWidget);
      expect(find.text('Credit grant'), findsOneWidget);
      expect(find.text('"Enjoy"'), findsOneWidget);
      expect(find.text('+3.0000'), findsOneWidget);
      expect(find.text('+2.2000'), findsOneWidget);
      expect(find.text('Oct 12, 2026'), findsOneWidget);
      // A receipt is copyable; a transaction links.
      expect(find.bySemanticsLabel('Copy receipt ID'), findsNWidgets(2));
      expect(find.byKey(const Key('billingReferenceLink')), findsOneWidget);
      // No other-wallet note on a keyfile account.
      expect(
          find.byKey(const Key('billingOtherWalletPurchases')), findsNothing);
    });

    testWidgets('an unknown row type still renders', (tester) async {
      historyIs([
        _page([
          {
            'type': 'arns',
            'date': '2026-10-01T00:00:00.000Z',
            'wincSpent': '5',
            'name': 'ardrive',
          },
          {'type': 'something-new'},
          {},
        ]),
      ]);
      await pumpPage(tester, user: _user());

      expect(tester.takeException(), isNull);
      expect(find.text('Other'), findsNWidgets(3));
      expect(find.text('ardrive'), findsOneWidget);
    });

    testWidgets('an empty history says so and offers Add credits',
        (tester) async {
      await pumpPage(tester, user: _user());
      expect(find.text('No purchases yet'), findsOneWidget);
      expect(find.byKey(const Key('billingEmptyAddCredits')), findsOneWidget);
      expect(find.byKey(const Key('billingDownloadCsv')), findsNothing);
    });

    testWidgets('a failed load says so and Try again loads', (tester) async {
      var fail = true;
      when(() => payments.getPaymentHistoryPage(
            wallet: any(named: 'wallet'),
            cursor: any(named: 'cursor'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async {
        if (fail) throw Exception('down');
        return _page([_card('2026-10-12T10:00:00.000Z', 500, 1)]);
      });
      await pumpPage(tester, user: _user());

      expect(find.text("Couldn't load your purchases. Try again."),
          findsOneWidget);
      fail = false;
      await tester.tap(find.byKey(const Key('billingPurchasesRetry')));
      await tester.pumpAndSettle();
      expect(find.text('\$5.00'), findsOneWidget);
    });

    testWidgets('Load more adds the next page with its cursor', (tester) async {
      historyIs([
        _page([_card('2026-10-12T10:00:00.000Z', 500, 1)],
            more: true, cursor: 'c1'),
        _page([_card('2026-09-12T10:00:00.000Z', 700, 2)]),
      ]);
      await pumpPage(tester, user: _user());

      expect(find.text('\$5.00'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('billingLoadMore')));
      await tester.tap(find.byKey(const Key('billingLoadMore')));
      await tester.pumpAndSettle();

      expect(find.text('\$5.00'), findsOneWidget);
      expect(find.text('\$7.00'), findsOneWidget);
      expect(find.byKey(const Key('billingLoadMore')), findsNothing);
      verify(() => payments.getPaymentHistoryPage(
            wallet: any(named: 'wallet'),
            cursor: 'c1',
            limit: any(named: 'limit'),
          )).called(1);
    });

    testWidgets('Download CSV has the Console columns and every page',
        (tester) async {
      historyIs([
        _page([_card('2026-10-12T10:00:00.000Z', 2500, 3)],
            more: true, cursor: 'c1'),
        _page([_crypto('2026-09-03T10:00:00.000Z')]),
      ]);
      await pumpPage(tester, user: _user());

      await tester.ensureVisible(find.byKey(const Key('billingDownloadCsv')));
      await tester.tap(find.byKey(const Key('billingDownloadCsv')));
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      expect(saved.single.$1, 'turbo-purchases.csv');
      final lines = saved.single.$2.split('\r\n');
      expect(lines[0],
          '"Date","Method","Amount","USD Value","Credits","Reference"');
      expect(lines[1],
          '"2026-10-12T10:00:00.000Z","Card","25 USD","25","3","pi_3QabcdefghijkX9"');
      expect(lines[2],
          '"2026-09-03T10:00:00.000Z","Crypto","2.5 AR","18.00","2.2","Hm3rAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAtW8c"');
      expect(lines, hasLength(3));
    });

    testWidgets('a CSV that cannot be saved says so', (tester) async {
      historyIs([
        _page([_card('2026-10-12T10:00:00.000Z', 500, 1)]),
      ]);
      await pumpPage(tester, user: _user(), saveThrows: true);
      await tester.ensureVisible(find.byKey(const Key('billingDownloadCsv')));
      await tester.tap(find.byKey(const Key('billingDownloadCsv')));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't save the CSV. Try again."), findsOneWidget);
    });
  });

  group('Wander account', () {
    testWidgets('waits for a button and loads on press', (tester) async {
      historyIs([
        _page([_card('2026-10-12T10:00:00.000Z', 500, 1)]),
      ]);
      await pumpPage(tester, user: _user(type: ProfileType.arConnect));

      verifyNever(() => payments.getPaymentHistoryPage(
            wallet: any(named: 'wallet'),
            cursor: any(named: 'cursor'),
            limit: any(named: 'limit'),
          ));
      expect(
          find.text('Wander asks you to approve. Nothing is charged or sent.'),
          findsOneWidget);
      expect(find.byKey(const Key('billingAddCredits')), findsOneWidget);

      await tester.tap(find.byKey(const Key('billingShowPurchases')));
      await tester.pumpAndSettle();

      expect(historyCalls(), 1);
      expect(find.text('\$5.00'), findsOneWidget);
      expect(find.byKey(const Key('billingShowPurchases')), findsNothing);
    });

    testWidgets('a refused approval says so, and Try again asks again',
        (tester) async {
      var refuse = true;
      when(() => payments.getPaymentHistoryPage(
            wallet: any(named: 'wallet'),
            cursor: any(named: 'cursor'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async {
        if (refuse) throw TurboSignatureException('Failed: cancelled');
        return _page([_card('2026-10-12T10:00:00.000Z', 500, 1)]);
      });
      await pumpPage(tester, user: _user(type: ProfileType.arConnect));

      await tester.tap(find.byKey(const Key('billingShowPurchases')));
      await tester.pumpAndSettle();
      expect(find.text("It wasn't approved. Try again."), findsOneWidget);
      expect(
          find.text("Couldn't load your purchases. Try again."), findsNothing);

      refuse = false;
      await tester.tap(find.byKey(const Key('billingPurchasesRetry')));
      await tester.pumpAndSettle();
      expect(find.text('\$5.00'), findsOneWidget);
    });

    testWidgets('a network failure is not called a refusal', (tester) async {
      when(() => payments.getPaymentHistoryPage(
            wallet: any(named: 'wallet'),
            cursor: any(named: 'cursor'),
            limit: any(named: 'limit'),
          )).thenThrow(Exception('offline'));
      await pumpPage(tester, user: _user(type: ProfileType.arConnect));
      await tester.tap(find.byKey(const Key('billingShowPurchases')));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load your purchases. Try again."),
          findsOneWidget);
    });

    testWidgets('purchases loaded once show again without asking',
        (tester) async {
      historyIs([
        _page([_card('2026-10-12T10:00:00.000Z', 500, 1)]),
      ]);
      final user = _user(type: ProfileType.arConnect);
      await pumpPage(tester, user: user);
      await tester.tap(find.byKey(const Key('billingShowPurchases')));
      await tester.pumpAndSettle();
      expect(historyCalls(), 1);

      // Leave and come back: the session cache answers.
      await tester.pumpWidget(const SizedBox());
      await pumpPage(tester, user: user);
      expect(find.byKey(const Key('billingShowPurchases')), findsNothing);
      expect(find.text('\$5.00'), findsOneWidget);
      verifyNever(() => payments.getPaymentHistoryPage(
            wallet: any(named: 'wallet'),
            cursor: any(named: 'cursor'),
            limit: any(named: 'limit'),
          ));
    });
  });

  group('Phantom account', () {
    testWidgets('hides AR at 0, shows the note and the credits to use',
        (tester) async {
      when(() => payments.getBalanceForAddress(
                address: _solana,
                walletType: WalletType.solana,
              ))
          .thenAnswer(
              (_) async => _credit * BigInt.from(42) ~/ BigInt.from(100));
      await pumpPage(
        tester,
        user: _user(source: _solana),
        solanaProvider: 'phantom',
      );

      expect(find.byKey(const Key('billingArRow')), findsNothing);
      expect(
        find.text(
            'Purchases made with your Phantom wallet in the ar.io Console show there.'),
        findsOneWidget,
      );
      expect(
          find.text('0.4200 credits on your Phantom wallet'), findsOneWidget);
      expect(find.byKey(const Key('billingUseCredits')), findsOneWidget);
      // Purchases load for the Arweave address with no prompt.
      expect(historyCalls(), 1);
    });

    testWidgets('shows AR when it is above 0', (tester) async {
      await pumpPage(
        tester,
        user: _user(source: _solana, ar: BigInt.from(5) * _credit),
        solanaProvider: 'phantom',
      );
      expect(find.byKey(const Key('billingArRow')), findsOneWidget);
    });

    testWidgets('no source row when the sign-in wallet has no credits',
        (tester) async {
      await pumpPage(tester,
          user: _user(source: _solana), solanaProvider: 'phantom');
      expect(find.byKey(const Key('billingSourceCredits')), findsNothing);
    });

    testWidgets('Use them shares all of it with the Arweave address',
        (tester) async {
      var balance = _credit * BigInt.from(2);
      when(() => payments.getBalanceForAddress(
            address: _solana,
            walletType: WalletType.solana,
          )).thenAnswer((_) async => balance);
      final sharing = _FakeSharing();
      await pumpPage(
        tester,
        user: _user(source: _solana),
        solanaProvider: 'phantom',
        sharing: sharing,
      );

      balance = BigInt.zero;
      await tester.tap(find.byKey(const Key('billingUseCredits')));
      await tester.pumpAndSettle();

      expect(sharing.shared, hasLength(1));
      expect(sharing.shared.single.from, _solana);
      expect(sharing.shared.single.to, _arweave);
      expect(sharing.shared.single.winc, _credit * BigInt.from(2));
      expect(find.byKey(const Key('billingSourceCredits')), findsNothing);
    });

    testWidgets('a refused share says so and keeps the row', (tester) async {
      when(() => payments.getBalanceForAddress(
            address: _solana,
            walletType: WalletType.solana,
          )).thenAnswer((_) async => _credit);
      await pumpPage(
        tester,
        user: _user(source: _solana),
        solanaProvider: 'phantom',
        sharing: _FakeSharing(fails: true),
      );

      await tester.tap(find.byKey(const Key('billingUseCredits')));
      await tester.pumpAndSettle();

      expect(find.text("That didn't go through. Try again."), findsOneWidget);
      expect(find.byKey(const Key('billingUseCredits')), findsOneWidget);
    });
  });

  group('MetaMask account', () {
    testWidgets('points to the Console with the full address to copy',
        (tester) async {
      when(() => payments.getBalanceForAddress(
            address: _ethereum,
            walletType: WalletType.ethereum,
          )).thenAnswer((_) async => _credit);
      await pumpPage(tester, user: _user(source: _ethereum), metaMask: true);

      expect(
          find.text('1.0000 credits on your MetaMask wallet'), findsOneWidget);
      expect(find.text('Share them in the ar.io Console'), findsOneWidget);
      expect(find.byKey(const Key('billingUseCredits')), findsNothing);
      expect(
          find.byKey(const Key('billingCopyArweaveAddress')), findsOneWidget);
      expect(
        find.text(
            'Purchases made with your MetaMask wallet in the ar.io Console show there.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('billingArRow')), findsNothing);
    });

    testWidgets('a Solana account the web cannot share for gets the Console',
        (tester) async {
      when(() => payments.getBalanceForAddress(
            address: _solana,
            walletType: WalletType.solana,
          )).thenAnswer((_) async => _credit);
      // The stub, as off the web: it cannot sign.
      await pumpPage(
        tester,
        user: _user(source: _solana),
        solanaProvider: 'phantom',
        sharing: CreditSharingService(),
      );
      expect(find.byKey(const Key('billingUseCredits')), findsNothing);
      expect(find.text('Share them in the ar.io Console'), findsOneWidget);
    });
  });

  group('shared credits', () {
    testWidgets('lists both groups read-only', (tester) async {
      when(() => payments.getBalanceDetails(wallet: any(named: 'wallet')))
          .thenAnswer((_) async => _details(
                own: 10,
                effective: 12,
                received: [
                  TurboCreditApproval(
                    approvedAddress: _arweave,
                    payingAddress: _solana,
                    approvedWinc: _credit * BigInt.from(3),
                    usedWinc: _credit,
                  ),
                ],
                given: [
                  TurboCreditApproval(
                    approvedAddress: _ethereum,
                    payingAddress: _arweave,
                    approvedWinc: _credit * BigInt.from(5),
                    usedWinc: _credit,
                    expiresAt: DateTime.utc(2099, 12, 1, 12),
                  ),
                ],
              ));
      await pumpPage(tester, user: _user());

      expect(find.text('Shared credits'), findsOneWidget);
      expect(find.text('Shared with you'), findsOneWidget);
      expect(find.text('You shared'), findsOneWidget);
      expect(find.text('2.0000 left · never expires'), findsOneWidget);
      expect(find.text('1.0000 of 5.0000 used · expires Dec 1, 2099'),
          findsOneWidget);
      // Read-only: nothing to revoke or share.
      expect(find.textContaining('Revoke'), findsNothing);
    });

    testWidgets('no section when nothing is shared', (tester) async {
      await pumpPage(tester, user: _user());
      expect(find.text('Shared credits'), findsNothing);
    });
  });

  group('session cache', () {
    test('is cleared when the account signs out', () async {
      final controller = StreamController<User?>();
      final c = BillingSessionCache(authChanges: controller.stream);
      c.storePurchases('a', purchases: const [], cursor: null, hasMore: false);
      expect(c.hasPurchasesFor('a'), isTrue);
      controller.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(c.hasPurchasesFor('a'), isFalse);
      await controller.close();
    });

    test('is cleared when another wallet signs in', () async {
      final controller = StreamController<User?>();
      final c = BillingSessionCache(authChanges: controller.stream);
      c.storePurchases(_arweave,
          purchases: const [], cursor: null, hasMore: false);
      controller.add(_user(address: 'B'));
      await Future<void>.delayed(Duration.zero);
      expect(c.hasPurchasesFor(_arweave), isFalse);
      await controller.close();
    });

    test('never answers for another wallet', () {
      final c = BillingSessionCache();
      c.storePurchases('a', purchases: const [], cursor: null, hasMore: false);
      expect(c.hasPurchasesFor('b'), isFalse);
    });
  });

  group('purchase rows', () {
    test('read defensively', () {
      final p = Purchase.fromJson({
        'type': 'crypto',
        'tokenType': 'brand-new-token',
        'tokenQuantity': 'not a number',
        'usdEquivalent': 'x',
        'wincCredited': 5,
      });
      expect(p.cryptoAmountText, 'BRAND-NEW-TOKEN');
      expect(p.usdText, isNull);
      expect(p.reference, isNull);
      expect(p.dateLabel, '');
      expect(purchasesCsv([p]), contains('"Crypto"'));
    });

    test('CSV quotes commas and quotes', () {
      final p = Purchase.fromJson({
        'type': 'fiat',
        'date': 'd',
        'paymentAmount': 100,
        'currencyType': 'usd',
        'receiptId': 'a"b,c',
        'wincCredited': '1000000000000',
      });
      expect(purchasesCsv([p]).split('\r\n')[1],
          '"d","Card","1 USD","1","1","a""b,c"');
    });

    test('tiny USD equivalents are not shown as 0', () {
      expect(
        Purchase.fromJson({'type': 'crypto', 'usdEquivalent': 0.004}).usdText,
        '~<\$0.01',
      );
      expect(
        Purchase.fromJson({'type': 'crypto', 'usdEquivalent': 0}).usdText,
        isNull,
      );
    });
  });

  group('route', () {
    test('/billing parses to the page and back', () async {
      final parser = AppRouteInformationParser();
      final path = await parser.parseRouteInformation(
        RouteInformation(uri: Uri.parse('/billing')),
      );
      expect(path.billing, isTrue);
      expect(
        parser.restoreRouteInformation(AppRoutePath.billing()).uri.path,
        '/billing',
      );
    });

    test('a longer path is not the page', () async {
      final path = await AppRouteInformationParser().parseRouteInformation(
        RouteInformation(uri: Uri.parse('/billing/x')),
      );
      expect(path.billing, isFalse);
    });

    test('back returns to what the page covered', () {
      final router = AppRouterDelegate()..showNames();
      router.showBilling();
      expect(router.showingBilling, isTrue);
      expect(router.showingNames, isFalse);
      expect(router.currentConfiguration.billing, isTrue);

      router.closeBilling();
      expect(router.showingBilling, isFalse);
      expect(router.showingNames, isTrue);
    });

    test('Account and Billing replace each other and back keeps the origin',
        () {
      final router = AppRouterDelegate()..showNames();
      router.showAccount();
      router.showBilling();
      expect(router.showingAccount, isFalse);
      expect(router.showingBilling, isTrue);
      router.closeBilling();
      expect(router.showingNames, isTrue);

      router.showBilling();
      router.showAccount();
      expect(router.showingBilling, isFalse);
      router.closeAccount();
      expect(router.showingNames, isTrue);
    });

    test('back from an opened address lands on the drives list', () async {
      final router = AppRouterDelegate();
      await router.setNewRoutePath(AppRoutePath.billing());
      expect(router.showingBilling, isTrue);
      router.closeBilling();
      expect(router.showingBilling, isFalse);
      expect(router.showingDrivesList, isTrue);
    });

    test('is shown only to somebody signed in', () {
      final router = AppRouterDelegate()..showBilling();
      expect(
        router.showsBilling(ProfileLoggedIn(user: _user(), useTurbo: false)),
        isTrue,
      );
      for (final state in [
        ProfilePromptAdd(),
        ProfilePromptLogIn(),
        ProfileCheckingAvailability(),
      ]) {
        expect(router.showsBilling(state), isFalse, reason: '$state');
      }
    });

    test('a link to it is honoured after sign-in', () async {
      final router = AppRouterDelegate();
      await router.setNewRoutePath(AppRoutePath.billing());
      router.signingIn = true;
      router.landAfterSignIn();
      expect(router.showingBilling, isTrue);
      expect(router.showingDrivesList, isFalse);
    });

    test('opening a drive or another page leaves it', () {
      final router = AppRouterDelegate()..showBilling();
      router.openDriveFromList('d1');
      expect(router.showingBilling, isFalse);

      router
        ..showBilling()
        ..showWebPages();
      expect(router.showingBilling, isFalse);
    });
  });
}
