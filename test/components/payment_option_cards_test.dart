import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/components/payment_method_selector_widget.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two ways to pay on the upload sheet, as option cards.
void main() {
  const keepTabOpen = 'Keep this tab open';

  UploadPaymentMethodInfo info({
    UploadMethod method = UploadMethod.turbo,
    bool arFine = true,
    bool creditsFine = true,
    bool noCredits = false,
  }) {
    UploadCostEstimate cost(int winston) => UploadCostEstimate(
          pstFee: BigInt.zero,
          totalCost: BigInt.from(winston),
          totalSize: 1,
          usdUploadCost: 1,
        );

    return UploadPaymentMethodInfo(
      uploadMethod: method,
      costEstimateTurbo: cost(4100000000),
      costEstimateAr: cost(7935750989),
      hasNoTurboBalance: noCredits,
      isTurboUploadPossible: true,
      arBalance: '1.0619',
      sufficientArBalance: arFine,
      turboCredits: noCredits ? '0' : '2.0370',
      sufficentCreditsBalance: creditsFine,
      freeStatus: FreeUploadStatus.notEligible,
      totalSize: 1,
    );
  }

  Future<void> pump(
    WidgetTester tester,
    UploadPaymentMethodInfo i, {
    void Function()? onArSelect,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
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
            body: SingleChildScrollView(
              child: PaymentMethodSelector(
                uploadMethodInfo: i,
                onTurboTopupSucess: () {},
                onArSelect: onArSelect ?? () {},
                onTurboSelect: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows both ways to pay with their cost and balance',
      (tester) async {
    await pump(tester, info());

    expect(find.text('Turbo Credits'), findsOneWidget);
    expect(find.text('0.0041 credits'), findsOneWidget);
    expect(find.text('2.0370 credits available'), findsOneWidget);
    expect(find.text('Wallet (AR)'), findsOneWidget);
    expect(find.text('0.0079 AR'), findsOneWidget);
    expect(find.text('1.0619 AR available'), findsOneWidget);
  });

  testWidgets('choosing the wallet card selects AR', (tester) async {
    var arSelected = false;
    await pump(tester, info(), onArSelect: () => arSelected = true);

    await tester.tap(find.text('Wallet (AR)'));
    await tester.pump();

    expect(arSelected, isTrue);
  });

  testWidgets('says on the card when a balance is not enough', (tester) async {
    await pump(tester, info(arFine: false, creditsFine: false));

    expect(find.text('Not enough AR, 1.0619 available'), findsOneWidget);
    expect(find.text('Not enough credits, 2.0370 available'), findsOneWidget);
  });

  testWidgets('says when there are no credits yet', (tester) async {
    await pump(tester, info(noCredits: true, creditsFine: false));

    expect(find.text('No credits yet'), findsOneWidget);
  });

  testWidgets('asks to keep the tab open when paying from the wallet',
      (tester) async {
    await pump(tester, info(method: UploadMethod.ar));

    expect(find.textContaining(keepTabOpen), findsOneWidget);
  });

  /// The wallet card is the default when there are no credits. It says AR is
  /// short; the way forward, adding credits, has to be offered as well.
  testWidgets('offers credits when neither balance can pay, wallet chosen',
      (tester) async {
    await pump(tester,
        info(method: UploadMethod.ar, arFine: false, creditsFine: false));

    expect(find.text('Not enough AR, 1.0619 available'), findsOneWidget);
    expect(
      find.textContaining('Add credits to upload', findRichText: true),
      findsOneWidget,
    );
    // Said as an error with its way out as a button, not as underlined red
    // text that a keyboard could not reach.
    final notice = tester.widget<ArDriveNotice>(find.byType(ArDriveNotice));
    expect(notice.type, ArDriveNoticeType.error);
    expect(notice.actionLabel, 'Add credits to upload');
  });

  testWidgets('with Turbo chosen and short, only offers to add credits',
      (tester) async {
    await pump(tester, info(creditsFine: false));

    expect(find.text('Not enough credits, 2.0370 available'), findsOneWidget);
    expect(find.text('Add credits to upload'), findsOneWidget);
    // A link that opens the top-up, announced as a button.
    expect(
      tester.getSemantics(find.text('Add credits to upload')),
      matchesSemantics(
        label: 'Add credits to upload',
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    expect(
      find.textContaining('Insufficient Credit balance', findRichText: true),
      findsNothing,
      reason: 'the Turbo card already says it',
    );
  });

  /// There is no upload to keep the tab open for.
  testWidgets('not while the wallet cannot pay', (tester) async {
    await pump(tester, info(method: UploadMethod.ar, arFine: false));

    expect(find.textContaining(keepTabOpen), findsNothing);
    expect(find.text('Not enough AR, 1.0619 available'), findsOneWidget);
  });
}
