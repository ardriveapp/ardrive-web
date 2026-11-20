import 'package:ardrive/blocs/upload/models/source_wallet_credits.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/components/charged_review_dialog.dart';
import 'package:ardrive/components/payment_method_selector_widget.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive/turbo/services/credit_sharing_service.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Sharing extends CreditSharingService {
  final shared = <BigInt>[];

  @override
  bool get isSupported => true;

  @override
  Future<void> shareCreditsFromSignInWallet({
    required String sourceAddress,
    required String approvedAddress,
    required BigInt approvedWinc,
  }) async {
    shared.add(approvedWinc);
  }
}

/// The snapshot reviews' shared dialog: the credits on a sign-in wallet are
/// found and shared here, as on the upload and deployment reviews.
void main() {
  final credit = BigInt.from(10).pow(12);
  late List<UploadMethod> confirmed;
  late int refreshed;
  late int cancelled;

  setUp(() {
    confirmed = [];
    refreshed = 0;
    cancelled = 0;
  });

  UploadCostEstimate estimate(BigInt cost) => UploadCostEstimate(
        pstFee: BigInt.zero,
        totalCost: cost,
        totalSize: 1,
        usdUploadCost: 0.31,
      );

  Future<void> pump(
    WidgetTester tester, {
    BigInt? balance,
    bool busy = false,
    bool arSufficient = false,
    Future<SourceWalletCredits?> Function(BuildContext)? lookUp,
    CreditSharingService? sharing,
    FreeUploadStatus freeStatus = FreeUploadStatus.notEligible,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ActivityTracker(),
        child: ArDriveTheme(
          themeData: lightTheme(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ChargedReviewDialog(
                title: 'Create snapshot',
                destination: 'To My Drive',
                primaryLabel: 'Create snapshot',
                busy: busy,
                onConfirm: confirmed.add,
                onCancel: () => cancelled++,
                refresh: () async => refreshed++,
                onMethodChanged: (_) {},
                method: UploadMethod.ar,
                totalSize: 1,
                costEstimateAr: estimate(BigInt.from(4000000000)),
                costEstimateTurbo: estimate(credit * BigInt.two),
                turboBalance: balance ?? BigInt.zero,
                turboCredits: '0',
                arBalance: '1',
                sufficientArBalance: arSufficient,
                freeStatus: freeStatus,
                files: const [
                  (
                    name: 'My Drive',
                    size: 2048,
                    contentType: 'application/json'
                  ),
                ],
                lookUpSourceCredits: lookUp,
                creditSharing: sharing,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    // Past the route's own entrance, which ignores touches.
    await tester.pump(const Duration(seconds: 1));
  }

  SourceWalletCredits found(WalletType type) => SourceWalletCredits(
        balance: credit * BigInt.from(3),
        sourceAddress: 'sourceAddress',
        walletType: type,
        arweaveAddress: 'arweaveAddress',
      );

  testWidgets('while confirming, the payment choice is held', (tester) async {
    await pump(tester, busy: true, arSufficient: true);

    final held = tester.widgetList<AbsorbPointer>(find.ancestor(
        of: find.byType(PaymentMethodSelector),
        matching: find.byType(AbsorbPointer)));
    expect(held.any((a) => a.absorbing), isTrue);
  });

  testWidgets('the snapshot is a real row, not an empty card', (tester) async {
    await pump(tester, balance: credit * BigInt.from(5));

    expect(find.text('My Drive'), findsOneWidget);
    expect(find.text('2 KiB'), findsOneWidget);
  });

  testWidgets('short of credits: credits on the sign-in wallet are said',
      (tester) async {
    await pump(
      tester,
      lookUp: (_) async => found(WalletType.solana),
      sharing: _Sharing(),
    );

    expect(find.byType(SourceWalletCreditsNotice), findsOneWidget);
    expect(find.text('Share credits'), findsOneWidget);
  });

  testWidgets('and shared in the app, then the balance is read again',
      (tester) async {
    final sharing = _Sharing();
    await pump(
      tester,
      lookUp: (_) async => found(WalletType.solana),
      sharing: sharing,
    );

    await tester.ensureVisible(find.text('Share credits'));
    await tester.tap(find.text('Share credits'));
    await tester.pump();
    await tester.pump();

    expect(sharing.shared, [credit * BigInt.from(3)]);
    expect(refreshed, 1);

    // Shared, they are in the balance now: not offered a second time.
    await tester.pumpAndSettle();
    expect(find.text('Share credits'), findsNothing);
    expect(find.byType(SourceWalletCreditsNotice), findsNothing);
  });

  testWidgets('an Ethereum wallet is told where its credits are, no button',
      (tester) async {
    await pump(
      tester,
      lookUp: (_) async => found(WalletType.ethereum),
      sharing: _Sharing(),
    );

    expect(find.byType(SourceWalletCreditsNotice), findsOneWidget);
    expect(find.text('Share credits'), findsNothing);
  });

  testWidgets('no credits there, no notice, and covered credits ask nothing',
      (tester) async {
    var asked = 0;
    await pump(tester, lookUp: (_) async {
      asked++;
      return null;
    });
    expect(find.byType(SourceWalletCreditsNotice), findsNothing);
    expect(asked, 1);

    await pump(tester, balance: credit * BigInt.from(5), lookUp: (_) async {
      asked++;
      return null;
    });
    expect(asked, 1, reason: 'asked only while credits are short');
  });

  testWidgets('the wallet is used only when picked, then Create pays with it',
      (tester) async {
    await pump(tester, balance: credit * BigInt.from(5), arSufficient: true);

    // Turbo Credits, though the cubit opened on the wallet.
    expect(find.textContaining(r'$0.31', findRichText: true), findsOneWidget);

    await tester.ensureVisible(find.text('Wallet (AR)'));
    await tester.tap(find.text('Wallet (AR)'));
    await tester.pump();
    await tester.pump();
    final create = tester.widget<ArDriveButtonNew>(
        find.widgetWithText(ArDriveButtonNew, 'Create snapshot'));
    expect(create.isDisabled, isFalse);
    create.onPressed!();
    await tester.pump();

    expect(confirmed, [UploadMethod.ar]);
  });

  testWidgets('with no Turbo price the wallet pays and the selector is legacy',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ActivityTracker(),
        child: ArDriveTheme(
          themeData: lightTheme(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ChargedReviewDialog(
                title: 'Create snapshot',
                destination: 'To My Drive',
                primaryLabel: 'Create snapshot',
                busy: false,
                onConfirm: confirmed.add,
                onCancel: () {},
                refresh: () async {},
                onMethodChanged: (_) {},
                method: UploadMethod.ar,
                totalSize: 1,
                costEstimateAr: estimate(BigInt.from(4000000000)),
                costEstimateTurbo: UploadCostEstimate.zero(),
                turboBalance: BigInt.zero,
                turboCredits: '0',
                arBalance: '1',
                sufficientArBalance: true,
                freeStatus: FreeUploadStatus.notEligible,
                files: const [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(PaymentMethodSelector), findsOneWidget);
    expect(find.widgetWithText(ArDriveButtonNew, 'Add credits'), findsNothing);
    await tester.tap(find.widgetWithText(ArDriveButtonNew, 'Create snapshot'));
    await tester.pump();
    expect(confirmed, [UploadMethod.ar]);
  });

  testWidgets('an unreadable balance: Try again, no Add credits, no Create',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ActivityTracker(),
        child: ArDriveTheme(
          themeData: lightTheme(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ChargedReviewDialog(
                title: 'Create snapshot',
                destination: 'To My Drive',
                primaryLabel: 'Create snapshot',
                busy: false,
                onConfirm: confirmed.add,
                onCancel: () {},
                refresh: () async => refreshed++,
                onMethodChanged: (_) {},
                method: UploadMethod.ar,
                totalSize: 1,
                costEstimateAr: estimate(BigInt.from(4000000000)),
                costEstimateTurbo: estimate(credit * BigInt.two),
                turboBalance: BigInt.zero,
                turboUnreachable: true,
                turboCredits: '0',
                arBalance: '0',
                sufficientArBalance: false,
                freeStatus: FreeUploadStatus.notEligible,
                files: const [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.widgetWithText(ArDriveButtonNew, 'Add credits'), findsNothing);
    expect(
        find.widgetWithText(ArDriveButtonNew, 'Create snapshot'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(refreshed, 1);
  });

  testWidgets('busy: Create spins, Cancel and the X are held', (tester) async {
    await pump(tester, busy: true, freeStatus: FreeUploadStatus.free);

    expect(find.byType(ArDriveSpinner), findsOneWidget);
    expect(
      tester
          .widget<ArDriveButtonNew>(
              find.widgetWithText(ArDriveButtonNew, 'Cancel'))
          .isDisabled,
      isTrue,
    );
    final x = find.ancestor(
      of: find.byWidgetPredicate(
          (w) => w is ArDriveIcon && w.icon == ArDriveIconsData.x),
      matching: find.byType(GestureDetector),
    );
    await tester.tap(x.first, warnIfMissed: false);
    expect(cancelled, 0);
  });
}
