import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/models/source_wallet_credits.dart';
import 'package:ardrive/blocs/upload/models/upload_plan.dart';
import 'package:ardrive/blocs/upload/payment_method/bloc/upload_payment_method_bloc.dart';
import 'package:ardrive/blocs/upload/payment_method/view/upload_payment_method_view.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBloc
    extends MockBloc<UploadPaymentMethodEvent, UploadPaymentMethodState>
    implements UploadPaymentMethodBloc {}

class _MockArweaveService extends Mock implements ArweaveService {}

class _MockUploadPlan extends Mock implements UploadPlan {}

class _MockUploadParams extends Mock implements UploadParams {}

/// The selector draws a share button whenever it is handed a way to share, so
/// this view decides whether there is one. Off the web the service is a stub
/// with nothing to sign with, and a button there could only ever fail.
void main() {
  late _MockBloc bloc;
  late _MockArweaveService arweave;

  setUp(() {
    bloc = _MockBloc();
    arweave = _MockArweaveService();

    when(() => arweave.getMempoolSizeFromArweave()).thenAnswer((_) async => 0);
    when(() => bloc.shareSourceWalletCredits()).thenAnswer((_) async => true);

    final cost = UploadCostEstimate(
      pstFee: BigInt.zero,
      totalCost: BigInt.from(100),
      totalSize: 1,
      usdUploadCost: 1,
    );

    whenListen(
      bloc,
      const Stream<UploadPaymentMethodState>.empty(),
      initialState: UploadPaymentMethodLoaded(
        canUpload: false,
        params: _MockUploadParams(),
        paymentMethodInfo: UploadPaymentMethodInfo(
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
          sourceWalletCredits: SourceWalletCredits(
            balance: BigInt.from(12080000000000),
            sourceAddress: '4WkBm7vD1qF9xYzAbCdEfGh',
            walletType: WalletType.solana,
            arweaveAddress: 'arweaveAddress1234567890',
          ),
        ),
      ),
    );
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
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
            home: RepositoryProvider<ArweaveService>.value(
              value: arweave,
              child: BlocProvider<UploadPaymentMethodBloc>.value(
                value: bloc,
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: UploadPaymentMethodView(
                      onUploadMethodChanged: (_, __, ___) {},
                      onError: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('offers the share where the wallet can sign', (tester) async {
    when(() => bloc.canShareSourceWalletCredits).thenReturn(true);

    await pump(tester);

    expect(find.textContaining('Solana wallet'), findsOneWidget);
    expect(find.text('Share credits'), findsOneWidget);
  });

  testWidgets('and withholds it where nothing can', (tester) async {
    when(() => bloc.canShareSourceWalletCredits).thenReturn(false);

    await pump(tester);

    expect(
      find.textContaining('Solana wallet'),
      findsOneWidget,
      reason: 'the reader still needs to know where the credits are',
    );
    expect(find.text('Share credits'), findsNothing);
  });
}
