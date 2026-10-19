import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/components/upload_review_cost.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The cost line on the upload's last review step.
void main() {
  UploadPaymentMethodInfo info({
    UploadMethod method = UploadMethod.turbo,
    FreeUploadStatus freeStatus = FreeUploadStatus.notEligible,
  }) {
    UploadCostEstimate cost(int winston) => UploadCostEstimate(
          pstFee: BigInt.zero,
          totalCost: BigInt.from(winston),
          totalSize: 1,
          usdUploadCost: 1,
        );

    return UploadPaymentMethodInfo(
      uploadMethod: method,
      costEstimateTurbo: cost(7784725527),
      costEstimateAr: cost(7935750989),
      hasNoTurboBalance: false,
      isTurboUploadPossible: true,
      arBalance: '1.0619',
      sufficientArBalance: true,
      turboCredits: '2.0370',
      sufficentCreditsBalance: true,
      freeStatus: freeStatus,
      totalSize: 1,
    );
  }

  Future<void> pump(WidgetTester tester, UploadPaymentMethodInfo i) async {
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
          home: Scaffold(body: UploadReviewCost(paymentInfo: i)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a Turbo upload shows its cost in credits', (tester) async {
    await pump(tester, info());

    expect(find.text('Cost: 0.0078 credits'), findsOneWidget);
  });

  testWidgets('a wallet upload shows its cost in AR', (tester) async {
    await pump(tester, info(method: UploadMethod.ar));

    expect(find.text('Cost: 0.0079 AR'), findsOneWidget);
  });

  testWidgets('a free upload shows the free message', (tester) async {
    await pump(tester, info(freeStatus: FreeUploadStatus.free));

    expect(find.textContaining('Cost: 0 credits'), findsOneWidget);
    expect(find.textContaining('free thanks to Turbo'), findsOneWidget);
  });
}
