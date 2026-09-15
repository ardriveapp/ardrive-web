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
import 'package:flutter_portal/flutter_portal.dart';
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
  UploadPaymentMethodInfo info({
    SourceWalletCredits? credits,
    UploadMethod method = UploadMethod.turbo,
    bool arFine = false,
    bool creditsFine = false,
  }) {
    final cost = UploadCostEstimate(
      pstFee: BigInt.zero,
      totalCost: BigInt.from(100),
      totalSize: 1,
      usdUploadCost: 1,
    );

    return UploadPaymentMethodInfo(
      uploadMethod: method,
      costEstimateTurbo: cost,
      costEstimateAr: cost,
      hasNoTurboBalance: true,
      isTurboUploadPossible: true,
      arBalance: '0',
      sufficientArBalance: arFine,
      turboCredits: '0',
      sufficentCreditsBalance: creditsFine,
      freeStatus: FreeUploadStatus.notEligible,
      uploadPlanForAR: _MockUploadPlan(),
      uploadPlanForTurbo: _MockUploadPlan(),
      totalSize: 1,
      sourceWalletCredits: credits,
    );
  }

  Future<void> pump(
    WidgetTester tester,
    UploadPaymentMethodInfo i, {
    Future<bool> Function()? onShare,
    bool useDropdown = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      // The dropdown is built on flutter_portal and needs one above it.
      Portal(
        child: ArDriveTheme(
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
                  onShareCredits: onShare,
                  useDropdown: useDropdown,
                ),
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

  group('the share control', () {
    testWidgets('is offered when the sheet can sign a grant', (tester) async {
      await pump(tester, info(credits: credits), onShare: () async => true);

      expect(find.text('Share credits'), findsOneWidget);
    });

    /// Off the web there is no extension to sign with. The notice still says
    /// where the money is, and names the address to send it to, because that
    /// is the only thing left that helps.
    testWidgets('is absent where nothing can sign, and the address is named',
        (tester) async {
      await pump(tester, info(credits: credits));

      expect(find.text('Share credits'), findsNothing);
      expect(find.textContaining('arweav'), findsOneWidget);
    });

    testWidgets('says so when the grant does not go through', (tester) async {
      await pump(tester, info(credits: credits), onShare: () async => false);

      await tester.tap(find.text('Share credits'));
      await tester.pumpAndSettle();

      expect(find.textContaining('did not go through'), findsOneWidget);

      // And falls back to the instructions, which are still true.
      expect(find.textContaining('in Turbo'), findsOneWidget);
    });

    /// A wallet extension that throws rather than returning false. The reader
    /// gets the same fallback either way, and never a broken sheet.
    testWidgets('and survives the wallet throwing at it', (tester) async {
      await pump(
        tester,
        info(credits: credits),
        onShare: () async => throw Exception('user rejected'),
      );

      await tester.tap(find.text('Share credits'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('did not go through'), findsOneWidget);
    });
  });

  /// The main upload sheet uses the dropdown. The notice used to live in the
  /// radio row, which the dropdown does not have, so the reader this was built
  /// for - on the main upload sheet - saw no notice, no share button, and the
  /// same upsell as before. Every assertion below runs in both modes.
  for (final dropdown in [false, true]) {
    final mode = dropdown ? 'dropdown' : 'radio';

    group('in $mode mode, with credits on the sign-in wallet', () {
      testWidgets('says where they are, once', (tester) async {
        await pump(
          tester,
          info(credits: credits),
          onShare: () async => true,
          useDropdown: dropdown,
        );

        expect(find.textContaining('Solana wallet'), findsOneWidget);
        expect(find.text('Share credits'), findsOneWidget);
      });

      /// Both refusal branches used to end in a tappable top-up. The second is
      /// the exact message in the support ticket that started this.
      testWidgets('offers no top-up of any kind', (tester) async {
        await pump(tester, info(credits: credits), useDropdown: dropdown);

        for (final upsell in [
          'Use Turbo Credits',
          'Add Credits',
          'add Turbo credits'
        ]) {
          expect(
            find.textContaining(upsell, findRichText: true),
            findsNothing,
            reason: '"$upsell" sells credits to somebody who already owns them',
          );
        }
      });

      testWidgets('with Turbo chosen and AR enough, still no "Add Credits"',
          (tester) async {
        await pump(
          tester,
          info(credits: credits, arFine: true),
          useDropdown: dropdown,
        );

        expect(find.textContaining('Solana wallet'), findsOneWidget);
        expect(find.textContaining('Add Credits', findRichText: true),
            findsNothing);
      });

      /// True, and not a sales pitch, so it stays - beside the way out.
      testWidgets('paying with AR and short of it, says both', (tester) async {
        await pump(
          tester,
          info(credits: credits, method: UploadMethod.ar),
          useDropdown: dropdown,
        );

        expect(
            find.text('Insufficient AR balance for purchase.'), findsOneWidget);
        expect(find.textContaining('Solana wallet'), findsOneWidget);
      });

      /// Not stuck, so nothing to explain.
      testWidgets('says nothing while AR can pay', (tester) async {
        await pump(
          tester,
          info(credits: credits, method: UploadMethod.ar, arFine: true),
          // Something that could sign, so a missing button means withheld.
          onShare: () async => true,
          useDropdown: dropdown,
        );

        expect(find.textContaining('Solana wallet'), findsNothing);
        expect(find.text('Share credits'), findsNothing);
      });
    });

    /// Somebody who genuinely has no credits anywhere keeps every top-up route.
    group('in $mode mode, with no credits anywhere', () {
      testWidgets('keeps "Add Credits" when Turbo is chosen', (tester) async {
        await pump(tester, info(arFine: true), useDropdown: dropdown);

        expect(find.textContaining('Add Credits', findRichText: true),
            findsWidgets);
      });

      testWidgets('keeps "add Turbo credits" when both are short',
          (tester) async {
        await pump(tester, info(), useDropdown: dropdown);

        expect(
          find.textContaining('add Turbo credits', findRichText: true),
          findsWidgets,
        );
      });
    });
  }
}
