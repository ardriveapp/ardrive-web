import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/models/source_wallet_credits.dart';
import 'package:ardrive/blocs/upload/models/upload_plan.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/components/payment_method_selector_widget.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockUploadPlan extends Mock implements UploadPlan {}

/// What the payment sheet says when the credits are on the other wallet.
///
/// Before this, `hasNoTurboBalance` led straight to "Use Turbo Credits" and the
/// top-up modal. Offering to sell more credits to somebody who has just bought
/// some, and is looking at a refusal because they are on their sign-in wallet,
/// is the worst answer available. It is also the answer a real user got.
void main() {
  UploadPaymentMethodInfo info({SourceWalletCredits? credits}) {
    final cost = UploadCostEstimate(
      pstFee: BigInt.zero,
      totalCost: BigInt.from(100),
      totalSize: 1,
      usdUploadCost: 1,
    );

    return UploadPaymentMethodInfo(
      uploadMethod: UploadMethod.turbo,
      costEstimateTurbo: cost,
      costEstimateAr: cost,
      hasNoTurboBalance: true,
      isTurboUploadPossible: true,
      arBalance: '0',
      sufficientArBalance: false,
      turboCredits: '0',
      sufficentCreditsBalance: false,
      freeStatus: FreeUploadStatus.notEligible,
      uploadPlanForAR: _MockUploadPlan(),
      uploadPlanForTurbo: _MockUploadPlan(),
      totalSize: 1,
      sourceWalletCredits: credits,
    );
  }

  Future<void> pump(WidgetTester tester, UploadPaymentMethodInfo i) async {
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
                onArSelect: () {},
                onTurboSelect: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  final credits = SourceWalletCredits(
    balance: BigInt.from(12080000000000),
    sourceAddress: '4WkBm7vD1qF9xYzAbCdEfGh',
    walletType: WalletType.solana,
    arweaveAddress: 'arweaveAddress1234567890',
  );

  testWidgets('names the chain and both addresses', (tester) async {
    await pump(tester, info(credits: credits));

    expect(find.textContaining('Solana wallet'), findsOneWidget);
    expect(find.textContaining('4WkBm7'), findsOneWidget);
    expect(
      find.textContaining('arweav'),
      findsOneWidget,
      reason: 'the reader has to know which address to share the credits to',
    );
  });

  /// The whole point. A refusal must not become a sales pitch.
  testWidgets('and does not offer to sell more credits', (tester) async {
    await pump(tester, info(credits: credits));

    expect(
      find.textContaining('Use Turbo Credits', findRichText: true),
      findsNothing,
      reason: 'they already bought credits; this is where the app used to ask '
          'them to buy again',
    );
  });

  /// Somebody who genuinely has none, anywhere, still gets the top-up offer.
  testWidgets('but still offers a top-up to somebody who has none',
      (tester) async {
    await pump(tester, info());

    expect(find.textContaining('Use Turbo Credits', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('Solana wallet'), findsNothing);
  });
}
