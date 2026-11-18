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

class _NoFunding implements UploadCreditsFunding {
  @override
  Future<BigInt> creditsFor(int amountUsd) async => BigInt.zero;
  @override
  Future<BigInt?> payByCard(int amountUsd) async => null;
  @override
  Future<bool> awaitCredits({required BigInt above}) async => true;
  @override
  void refresh() {}
}

UploadReviewSummary _free() => UploadReviewSummary.fromPaymentInfo(
      UploadPaymentMethodInfo(
        uploadMethod: UploadMethod.turbo,
        costEstimateTurbo: UploadCostEstimate(
          pstFee: BigInt.zero,
          totalCost: BigInt.zero,
          totalSize: 1,
          usdUploadCost: 0,
        ),
        costEstimateAr: UploadCostEstimate(
          pstFee: BigInt.zero,
          totalCost: BigInt.from(100),
          totalSize: 1,
          usdUploadCost: null,
        ),
        hasNoTurboBalance: true,
        isTurboUploadPossible: true,
        arBalance: '0',
        sufficientArBalance: false,
        turboCredits: '0',
        sufficentCreditsBalance: false,
        freeStatus: FreeUploadStatus.free,
        totalSize: 1,
        turboBalanceWinc: BigInt.zero,
      ),
    );

/// The files on the upload review: one card, whatever the number of files,
/// quiet enough that a long list doesn't crowd out the cost.
void main() {
  Future<void> pump(WidgetTester tester, int count) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ArDriveTheme(
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
                title: 'Upload $count files',
                destination: 'To My files',
                files: [
                  for (var i = 0; i < count; i++)
                    (
                      name: 'file-$i.txt',
                      size: 1000,
                      contentType: 'text/plain'
                    ),
                ],
                summary: _free(),
                primaryLabel: 'Upload',
                onUpload: (_) {},
                onCancel: () {},
                funding: _NoFunding(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The card the rows sit in: the nearest decorated box around a file name.
  Rect cardOf(WidgetTester tester, String name) => tester.getRect(
        find
            .ancestor(
              of: find.text(name),
              matching: find.byWidgetPredicate((w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration as BoxDecoration).borderRadius != null),
            )
            .first,
      );

  testWidgets('one file: the file in its card, and no total', (tester) async {
    await pump(tester, 1);

    expect(find.text('file-0.txt'), findsOneWidget);
    expect(find.textContaining('total'), findsNothing);
  });

  testWidgets('a few files share one card, which ends in their total',
      (tester) async {
    await pump(tester, 3);

    final card = cardOf(tester, 'file-0.txt');
    expect(cardOf(tester, 'file-2.txt'), card);
    final total = find.textContaining(' total');
    expect(total, findsOneWidget);
    expect(card.contains(tester.getCenter(total)), isTrue);
    expect(find.textContaining('more'), findsNothing);
  });

  testWidgets('many files: the first four, then Show N more, in the card',
      (tester) async {
    await pump(tester, 9);

    expect(find.text('file-3.txt'), findsOneWidget);
    expect(find.text('file-4.txt'), findsNothing);
    final more = find.text('Show 5 more');
    expect(more, findsOneWidget);
    expect(
        cardOf(tester, 'file-0.txt').contains(tester.getCenter(more)), isTrue);
    expect(find.textContaining(' total'), findsOneWidget);
  });

  testWidgets('Show all lists them inside the card, which scrolls',
      (tester) async {
    await pump(tester, 30);
    final before = cardOf(tester, 'file-0.txt').height;

    await tester.tap(find.text('Show 26 more'));
    await tester.pumpAndSettle();

    expect(find.text('Show fewer'), findsOneWidget);
    // Capped: thirty rows would push the cost and Upload off the dialog.
    final after = cardOf(tester, 'file-0.txt').height;
    expect(after, greaterThan(before));
    expect(after, lessThan(44 * 8.0));
    await tester.scrollUntilVisible(find.text('file-29.txt'), 200,
        scrollable: find.descendant(
            of: find.byType(ListView), matching: find.byType(Scrollable)));
    expect(find.text('file-29.txt'), findsOneWidget);
  });
}
