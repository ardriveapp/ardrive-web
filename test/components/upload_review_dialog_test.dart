import 'dart:async';

import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/models/upload_review_summary.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/components/upload_review_dialog.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// One credit, in winston credits.
final _credit = BigInt.from(10).pow(12);
BigInt credits(double c) =>
    BigInt.from((c * 10000).round()) * _credit ~/ BigInt.from(10000);

class _FakeFunding implements UploadCreditsFunding {
  final quotes = {
    10: credits(1.8277),
    25: credits(4.5694),
    50: credits(9.1388),
    100: credits(18.2776),
  };
  var failQuotes = false;
  final paid = <int>[];
  Completer<BigInt?> payment = Completer();
  var waited = 0;
  var refreshed = 0;

  @override
  Future<BigInt> creditsFor(int amountUsd) async {
    if (failQuotes) throw Exception('unreachable');
    return quotes[amountUsd]!;
  }

  @override
  Future<BigInt?> payByCard(int amountUsd) {
    paid.add(amountUsd);
    return payment.future;
  }

  var landed = true;

  @override
  Future<bool> awaitCredits({required BigInt above}) async {
    waited++;
    return landed;
  }

  @override
  void refresh() => refreshed++;
}

UploadReviewSummary summary({
  FreeUploadStatus freeStatus = FreeUploadStatus.notEligible,
  double balance = 0,
  bool unreachable = false,
}) =>
    UploadReviewSummary.fromPaymentInfo(
      UploadPaymentMethodInfo(
        uploadMethod: UploadMethod.turbo,
        costEstimateTurbo: UploadCostEstimate(
          pstFee: BigInt.zero,
          totalCost: credits(5.875),
          totalSize: 1,
          usdUploadCost: 32.14,
        ),
        costEstimateAr: UploadCostEstimate(
          pstFee: BigInt.zero,
          totalCost: BigInt.from(100),
          totalSize: 1,
          usdUploadCost: null,
        ),
        hasNoTurboBalance: balance == 0,
        isTurboUploadPossible: true,
        arBalance: '0',
        sufficientArBalance: false,
        turboCredits: '0',
        sufficentCreditsBalance: false,
        freeStatus: freeStatus,
        totalSize: 1,
        turboBalanceWinc: credits(balance),
        turboUnreachable: unreachable,
      ),
    );

void main() {
  late _FakeFunding funding;
  late int uploads;
  late List<UploadMethod> methods;
  late int shown;
  late int cancels;

  setUp(() {
    uploads = 0;
    methods = [];
    shown = 0;
    cancels = 0;
  });

  Widget host(UploadReviewSummary? s) => ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: Scaffold(
            body: Center(
              child: UploadReviewDialog(
                title: 'Upload 3 files',
                destination: 'To My files, private',
                files: const [
                  (
                    name: 'recipes.pdf',
                    size: 31000,
                    contentType: 'application/pdf'
                  ),
                  (name: 'grandma.jpg', size: 96000, contentType: 'image/jpeg'),
                  (name: 'notes.txt', size: 2000, contentType: 'text/plain'),
                ],
                summary: s,
                primaryLabel: 'Upload',
                onUpload: (method) {
                  uploads++;
                  methods.add(method);
                },
                onShown: () => shown++,
                onCancel: () => cancels++,
                funding: funding,
              ),
            ),
          ),
        ),
      );

  Future<void> pump(WidgetTester tester, UploadReviewSummary? s) async {
    // Made in the test's own zone, so its futures complete as the test pumps.
    funding = _FakeFunding();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(s));
    await tester.pump();
  }

  Finder button(String label) => find.ancestor(
      of: find.text(label), matching: find.byType(ArDriveButtonNew));

  bool enabled(WidgetTester tester, String label) =>
      !tester.widget<ArDriveButtonNew>(button(label)).isDisabled;

  testWidgets('free: the files, Free, and Upload', (tester) async {
    await pump(tester, summary(freeStatus: FreeUploadStatus.free));

    expect(find.text('Upload 3 files'), findsOneWidget);
    expect(find.text('To My files, private'), findsOneWidget);
    expect(find.text('grandma.jpg'), findsOneWidget);
    expect(find.text('Free', findRichText: true), findsOneWidget);
    expect(
        find.text(
            'Covered by your free upload allowance. Saved for good, paid once.'),
        findsOneWidget);
    expect(enabled(tester, 'Upload'), isTrue);

    await tester.tap(button('Upload'));
    expect(uploads, 1);
    expect(methods, [UploadMethod.turbo],
        reason: 'the upload is paid the way the review showed');
    expect(shown, 1);
  });

  testWidgets('not free and not covered: the notice, and no Upload',
      (tester) async {
    await pump(tester, summary(freeStatus: FreeUploadStatus.allowanceUsedUp));

    expect(find.text('\$32.14 USD', findRichText: true), findsOneWidget);
    expect(
        find.text(
            'Paid once with Turbo Credits. Saved for good, no subscription.'),
        findsOneWidget);
    expect(
      find.text('This upload is over your free upload allowance. You have '
          '0.0000 credits, and it needs 5.8750. Add Turbo Credits to upload '
          'it.'),
      findsOneWidget,
    );
    expect(find.text('Upload'), findsNothing);
    expect(button('Add credits'), findsOneWidget);
  });

  testWidgets('Add credits: amounts, what they buy, and what is left',
      (tester) async {
    await pump(tester, summary());
    await tester.tap(button('Add credits'));
    await tester.pumpAndSettle();

    expect(find.text('Add Turbo Credits'), findsOneWidget);
    expect(find.text('This upload needs 5.8750 credits. Credits never expire.'),
        findsOneWidget);
    for (final amount in ['\$10', '\$25', '\$50', '\$100']) {
      expect(find.text(amount), findsOneWidget);
    }
    // The smallest amount that covers it is chosen.
    expect(find.text('9.1388 credits', findRichText: true), findsOneWidget);
    expect(
        find.text('Enough for this upload, with 3.2638 credits left. '
            'Next, pay by card.'),
        findsOneWidget);

    await tester.tap(find.text('\$10'));
    await tester.pump();
    expect(find.text('1.8277 credits', findRichText: true), findsOneWidget);
    expect(find.text('Not enough for this upload. Next, pay by card.'),
        findsOneWidget);

    await tester.tap(button('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Upload 3 files'), findsOneWidget);
  });

  testWidgets('a payment cancelled or refused goes back to the review',
      (tester) async {
    await pump(tester, summary());
    await tester.tap(button('Add credits'));
    await tester.pumpAndSettle();
    await tester.tap(button('Continue to payment'));
    await tester.pump();
    expect(funding.paid, [50]);

    funding.payment.complete(null);
    await tester.pumpAndSettle();

    expect(find.text('Upload 3 files'), findsOneWidget);
    expect(button('Add credits'), findsOneWidget);
    expect(funding.refreshed, 0);
    expect(uploads, 0);
  });

  testWidgets('paid: waits for the credits, reads again, then says so',
      (tester) async {
    await pump(tester, summary());
    await tester.tap(button('Add credits'));
    await tester.pumpAndSettle();
    await tester.tap(button('Continue to payment'));
    await tester.pump();

    funding.payment.complete(credits(9.1388));
    // The wait spins, so it never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(funding.waited, 1);
    expect(funding.refreshed, 1);

    // Until the fresh read is in, the wait, not the summary from before the
    // payment and its Add credits.
    expect(find.text('Adding your credits'), findsOneWidget);
    expect(find.text('Add credits'), findsNothing);

    // The review is read again with the new balance.
    await tester.pumpWidget(host(null));
    await tester.pump();
    expect(find.text('Add credits'), findsNothing);
    await tester.pumpWidget(host(summary(balance: 9.1388)));
    await tester.pump();

    expect(
        find.text("9.1388 credits added. You'll have 3.2638 credits left "
            'after this upload.'),
        findsOneWidget);
    expect(enabled(tester, 'Upload'), isTrue);
  });

  testWidgets('no price from Turbo: a clear message, a retry, no Upload',
      (tester) async {
    await pump(tester, summary(unreachable: true));

    expect(
        find.text("Couldn't get a price for this upload. Check your "
            'connection and try again.'),
        findsOneWidget);
    expect(find.text('Upload'), findsNothing);
    expect(find.text('Add credits'), findsNothing);

    await tester.tap(find.text('Try again'));
    expect(funding.refreshed, 1);
  });

  testWidgets('no quote for the amounts: a retry, and no payment',
      (tester) async {
    await pump(tester, summary());
    funding.failQuotes = true;
    await tester.tap(button('Add credits'));
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsOneWidget);
    expect(enabled(tester, 'Continue to payment'), isFalse);
  });

  testWidgets('while the price is read, Upload waits', (tester) async {
    await pump(tester, null);

    expect(enabled(tester, 'Upload'), isFalse);
  });

  testWidgets(
      'credits slow to arrive: keeps waiting, offers to check again, '
      'and never goes back to Add credits', (tester) async {
    await pump(tester, summary());
    funding.landed = false;
    await tester.tap(button('Add credits'));
    await tester.pumpAndSettle();
    await tester.tap(button('Continue to payment'));
    await tester.pump();
    funding.payment.complete(credits(9.1388));
    // The wait spins, so it never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Adding your credits'), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);
    expect(find.text('Add credits'), findsNothing);
    expect(funding.refreshed, 0);

    // They land.
    funding.landed = true;
    await tester.tap(find.text('Check again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(funding.refreshed, 1);

    // Read again, still short: still the wait, with Check again.
    await tester.pumpWidget(host(null));
    await tester.pump();
    await tester.pumpWidget(host(summary()));
    await tester.pump();
    expect(find.text('Check again'), findsOneWidget);
    expect(find.text('Add credits'), findsNothing);
  });

  testWidgets(
      'Upload stays off when the upload is not covered and there is '
      'nothing to add', (tester) async {
    // Only the wallet can take it, and the wallet can't pay.
    await pump(
      tester,
      UploadReviewSummary.fromPaymentInfo(
        UploadPaymentMethodInfo(
          uploadMethod: UploadMethod.ar,
          costEstimateTurbo: null,
          costEstimateAr: UploadCostEstimate(
            pstFee: BigInt.zero,
            totalCost: BigInt.from(100),
            totalSize: 1,
            usdUploadCost: null,
          ),
          hasNoTurboBalance: true,
          isTurboUploadPossible: false,
          arBalance: '0',
          sufficientArBalance: false,
          turboCredits: '0',
          sufficentCreditsBalance: false,
          freeStatus: FreeUploadStatus.notEligible,
          totalSize: 1,
        ),
      ),
    );

    expect(enabled(tester, 'Upload'), isFalse);
    await tester.tap(button('Upload'), warnIfMissed: false);
    expect(uploads, 0);
  });
}
