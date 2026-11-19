import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
import 'package:ardrive/blocs/create_manifest/create_manifest_cubit.dart';
import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/payment_method/bloc/upload_payment_method_bloc.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/components/create_manifest_form.dart';
import 'package:ardrive/components/upload_review_dialog.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/core/upload/uploader.dart' show UploadParams;
import 'package:ardrive/models/models.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockCreateManifestCubit extends MockCubit<CreateManifestState>
    implements CreateManifestCubit {}

class _MockPaymentBloc
    extends MockBloc<UploadPaymentMethodEvent, UploadPaymentMethodState>
    implements UploadPaymentMethodBloc {}

class _MockNames extends MockCubit<ArNSNameDialogState>
    implements ArNSFlowNameCubit {}

class _MockWallet extends MockCubit<ArNSWalletState>
    implements ArNSWalletCubit {}

class _FakeParams extends Fake implements UploadParams {}

/// The deployment review: the upload review's own dialog and cost block, with
/// what only a deployment says kept in it.
void main() {
  late _MockCreateManifestCubit cubit;
  late _MockPaymentBloc payment;

  setUpAll(() {
    registerFallbackValue(UploadMethod.turbo);
  });

  setUp(() {
    cubit = _MockCreateManifestCubit();
    payment = _MockPaymentBloc();
    when(() => payment.canShareSourceWalletCredits).thenReturn(false);
    when(() => cubit.uploadManifest(method: any(named: 'method')))
        .thenAnswer((_) async {});
  });

  final credit = BigInt.from(10).pow(12);

  UploadPaymentMethodInfo info({
    FreeUploadStatus freeStatus = FreeUploadStatus.notEligible,
    double balance = 5,
    bool turbo = true,
  }) =>
      UploadPaymentMethodInfo(
        uploadMethod: UploadMethod.turbo,
        costEstimateTurbo: turbo
            ? UploadCostEstimate(
                pstFee: BigInt.zero,
                totalCost: credit * BigInt.two,
                totalSize: 425,
                usdUploadCost: 0.31,
              )
            : null,
        costEstimateAr: UploadCostEstimate(
          pstFee: BigInt.zero,
          totalCost: BigInt.from(4000000000),
          totalSize: 425,
          usdUploadCost: null,
        ),
        hasNoTurboBalance: balance == 0,
        isTurboUploadPossible: turbo,
        arBalance: '0',
        sufficientArBalance: false,
        turboCredits: '$balance',
        sufficentCreditsBalance: balance >= 2,
        freeStatus: freeStatus,
        totalSize: 425,
        turboBalanceWinc: BigInt.from((balance * 1000000).round()) *
            credit ~/
            BigInt.from(1000000),
      );

  Future<void> pumpReview(
    WidgetTester tester, {
    UploadPaymentMethodState? paymentState,
    bool pending = false,
    ArNSFlowNameCubit? names,
    Size size = const Size(1200, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final file = await IOFile.fromData(
      Uint8List(425),
      name: 'e2e-names-site',
      lastModifiedDate: DateTime(2026),
    );
    whenListen(
      cubit,
      const Stream<CreateManifestState>.empty(),
      initialState: CreateManifestUploadReview(
        manifestSize: 425,
        manifestName: 'e2e-names-site',
        folderHasPendingFiles: pending,
        manifestFile: file,
        drive: Drive(
          id: 'drive-1',
          rootFolderId: 'root',
          ownerAddress: 'owner',
          name: 'A public drive',
          privacy: 'public',
          lastBlockHeight: 0,
          isHidden: false,
          dateCreated: DateTime(2024),
          lastUpdated: DateTime(2024),
        ),
        parentFolder: FolderEntry(
          id: 'root',
          driveId: 'drive-1',
          name: 'root',
          path: '',
          dateCreated: DateTime(2024),
          lastUpdated: DateTime(2024),
          isGhost: false,
          isHidden: false,
        ),
      ),
    );
    whenListen(
      payment,
      const Stream<UploadPaymentMethodState>.empty(),
      initialState: paymentState ??
          UploadPaymentMethodLoaded(
            params: _FakeParams(),
            paymentMethodInfo: info(freeStatus: FreeUploadStatus.free),
            canUpload: true,
          ),
    );

    final wallet = _MockWallet();
    whenListen(
      wallet,
      const Stream<ArNSWalletState>.empty(),
      initialState: const ArNSWalletState(),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ActivityTracker()),
          if (names != null) BlocProvider<ArNSWalletCubit>.value(value: wallet),
        ],
        child: ArDriveApp(
          builder: (context) => MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: BlocProvider<CreateManifestCubit>.value(
                  value: cubit,
                  child: CreateManifestForm(names: names, paymentBloc: payment),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder primary(String text) => find.widgetWithText(ArDriveButtonNew, text);

  // With the name step open, the review was taller than a laptop window and
  // did not scroll, so Create deployment sat below the window, out of reach.
  testWidgets('Create deployment stays in view on a short window',
      (tester) async {
    await pumpReview(tester, size: const Size(1200, 520), pending: true);

    expect(tester.takeException(), isNull);
    final create = primary('Create deployment');
    expect(create, findsOneWidget);
    expect(tester.getBottomRight(create).dy, lessThanOrEqualTo(520));
  });

  testWidgets('free: the upload review, with the deployment in it',
      (tester) async {
    await pumpReview(tester, pending: true);

    expect(find.byType(UploadReviewDialog), findsOneWidget);
    expect(find.byType(UploadCostBlock), findsOneWidget);
    expect(find.text('Cost'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    // What the deployment says: its name and size, where it goes, the
    // pending files, and that it is public.
    expect(find.text('e2e-names-site'), findsOneWidget);
    expect(find.text('To A public drive'), findsOneWidget);
    expect(find.byType(ArDriveNotice), findsOneWidget);
    expect(
        find.textContaining('permanently viewable by anyone'), findsOneWidget);
    // Not the old words and widgets.
    expect(find.textContaining('Uploads this small are free'), findsNothing);
    expect(find.textContaining('credits available'), findsNothing);
    expect(primary('Create deployment'), findsOneWidget);
  });

  testWidgets('no pending files, no warning', (tester) async {
    await pumpReview(tester);

    expect(find.byType(ArDriveNotice), findsNothing);
  });

  testWidgets('paid with Turbo Credits: the cost in dollars, then it creates',
      (tester) async {
    await pumpReview(
      tester,
      paymentState: UploadPaymentMethodLoaded(
        params: _FakeParams(),
        paymentMethodInfo: info(),
        canUpload: true,
      ),
    );

    expect(find.byType(UploadCostBlock), findsOneWidget);
    expect(find.textContaining(r'$0.31', findRichText: true), findsOneWidget);
    expect(find.text('Paid with Turbo Credits'), findsOneWidget);

    await tester.tap(primary('Create deployment'));
    await tester.pump();

    verify(() => cubit.uploadManifest(method: UploadMethod.turbo)).called(1);
  });

  testWidgets('short of credits: Add credits, never Create deployment',
      (tester) async {
    await pumpReview(
      tester,
      paymentState: UploadPaymentMethodLoaded(
        params: _FakeParams(),
        paymentMethodInfo: info(balance: 0),
        canUpload: false,
      ),
    );

    expect(find.byType(UploadCostBlock), findsOneWidget);
    expect(primary('Add credits'), findsOneWidget);
    expect(primary('Create deployment'), findsNothing);
    verifyNever(() => cubit.uploadManifest(method: any(named: 'method')));
  });

  testWidgets('the price is being read: a wait, and Create deployment is off',
      (tester) async {
    await pumpReview(tester, paymentState: const UploadPaymentMethodLoading());

    expect(find.byType(UploadCostBlock), findsNothing);
    expect(find.byType(ArDriveSpinner), findsOneWidget);
    expect(
      tester.widget<ArDriveButtonNew>(primary('Create deployment')).isDisabled,
      isTrue,
    );
  });

  testWidgets('no price: it says so, and offers nothing to create',
      (tester) async {
    await pumpReview(tester, paymentState: UploadPaymentMethodError());

    expect(find.byType(UploadCostBlock), findsNothing);
    expect(primary('Create deployment'), findsNothing);
  });

  testWidgets('two fast presses make one deployment, busy until it is done',
      (tester) async {
    final gate = Completer<void>();
    when(() => cubit.uploadManifest(method: any(named: 'method')))
        .thenAnswer((_) => gate.future);
    await pumpReview(tester);

    final create = primary('Create deployment');
    tester.widget<ArDriveButtonNew>(create).onPressed!();
    tester.widget<ArDriveButtonNew>(create).onPressed!();
    await tester.pump();

    verify(() => cubit.uploadManifest(method: UploadMethod.turbo)).called(1);
    expect(find.byType(ArDriveSpinner), findsOneWidget);
    expect(
      tester.widget<ArDriveButtonNew>(primary('Cancel')).isDisabled,
      isTrue,
    );

    gate.complete();
    await tester.pump();
  });

  group('with a name step', () {
    late _MockNames names;
    var ready = false;

    setUp(() {
      names = _MockNames();
      ready = false;
      when(() => names.ready).thenAnswer((_) => ready);
      when(() => names.hasWork).thenReturn(false);
      when(() => names.close()).thenAnswer((_) async {});
      whenListen(
        names,
        const Stream<ArNSNameDialogState>.empty(),
        initialState:
            const ArNSNameDialogState(mode: ArNSNameDialogMode.nameItem),
      );
    });

    testWidgets('Create deployment waits until the name is ready',
        (tester) async {
      await pumpReview(tester, names: names);
      // The name row's label overflows in the test font; its layout is not
      // what this checks.
      tester.takeException();

      expect(find.byType(UploadCostBlock), findsOneWidget);
      expect(
        tester
            .widget<ArDriveButtonNew>(primary('Create deployment'))
            .isDisabled,
        isTrue,
      );
    });

    testWidgets('and offers it once the name is ready', (tester) async {
      ready = true;
      await pumpReview(tester, names: names);
      tester.takeException();

      expect(
        tester
            .widget<ArDriveButtonNew>(primary('Create deployment'))
            .isDisabled,
        isFalse,
      );
    });
  });
}
