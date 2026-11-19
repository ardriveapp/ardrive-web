import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog.dart'
    show ArNSFlowNameSection;
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
    registerFallbackValue(<ArNSNameRecord>[]);
    registerFallbackValue(PrepareUploadPaymentMethod(params: _FakeParams()));
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
    Stream<UploadPaymentMethodState>? paymentStream,
    bool pending = false,
    ArNSFlowNameCubit? names,
    Future<List<ArNSNameRecord>> Function(String)? lookupFollowing,
    String? existingManifestFileId,
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
        existingManifestFileId: existingManifestFileId,
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
      paymentStream ?? const Stream<UploadPaymentMethodState>.empty(),
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
                  child: CreateManifestForm(
                    names: names,
                    paymentBloc: payment,
                    lookupFollowing: lookupFollowing,
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

  testWidgets('the wallet is used only when picked, then Create pays with it',
      (tester) async {
    final states = StreamController<UploadPaymentMethodState>();
    addTearDown(states.close);
    final loaded = UploadPaymentMethodLoaded(
      params: _FakeParams(),
      paymentMethodInfo: info().copyWith(sufficientArBalance: true),
      canUpload: true,
    );
    when(() => payment.add(any())).thenAnswer((invocation) {
      final event = invocation.positionalArguments.first;
      if (event is ChangeUploadPaymentMethod) {
        states.add(UploadPaymentMethodLoaded(
          params: _FakeParams(),
          paymentMethodInfo: loaded.paymentMethodInfo.copyWith(
            uploadMethod: UploadMethod.ar,
            arChosen: true,
          ),
          canUpload: true,
        ));
      }
    });
    await pumpReview(
      tester,
      paymentState: loaded,
      paymentStream: states.stream,
    );
    await tester.pump(const Duration(seconds: 1));

    // Turbo Credits first, the wallet an offered choice.
    expect(find.textContaining(r'$0.31', findRichText: true), findsOneWidget);
    await tester.ensureVisible(find.text('Wallet (AR)'));
    await tester.tap(find.text('Wallet (AR)'));
    await tester.pump();
    await tester.pump();

    tester.widget<ArDriveButtonNew>(primary('Create deployment')).onPressed!();
    await tester.pump();

    verify(() => cubit.uploadManifest(method: UploadMethod.ar)).called(1);
  });

  testWidgets('no Turbo price: the wallet-only review, Create pays with it',
      (tester) async {
    await pumpReview(
      tester,
      paymentState: UploadPaymentMethodLoaded(
        params: _FakeParams(),
        paymentMethodInfo: info(turbo: false)
            .copyWith(sufficientArBalance: true, uploadMethod: UploadMethod.ar),
        canUpload: true,
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(UploadCostBlock), findsOneWidget);
    expect(find.text('Wallet (AR)'), findsOneWidget);
    tester.widget<ArDriveButtonNew>(primary('Create deployment')).onPressed!();
    await tester.pump();

    verify(() => cubit.uploadManifest(method: UploadMethod.ar)).called(1);
  });

  testWidgets('a wallet that changed says so, with nothing to try again',
      (tester) async {
    await pumpReview(tester, paymentState: UploadPaymentMethodWalletMismatch());

    expect(find.byType(UploadCostBlock), findsNothing);
    expect(find.textContaining('wallet changed'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(primary('Create deployment'), findsNothing);
    expect(primary('Close'), findsOneWidget);
  });

  testWidgets('busy: the X is held as well as Cancel', (tester) async {
    final gate = Completer<void>();
    when(() => cubit.uploadManifest(method: any(named: 'method')))
        .thenAnswer((_) => gate.future);
    await pumpReview(tester);
    tester.widget<ArDriveButtonNew>(primary('Create deployment')).onPressed!();
    await tester.pump();

    final x = find.ancestor(
      of: find.byWidgetPredicate(
          (w) => w is ArDriveIcon && w.icon == ArDriveIconsData.x),
      matching: find.byType(GestureDetector),
    );
    expect(tester.widget<GestureDetector>(x.first).onTap, isNull);

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
      when(() => names.setFollowing(any())).thenReturn(null);
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

    testWidgets(
        'the names and the payment choice are held while Create is '
        'being answered', (tester) async {
      ready = true;
      final gate = Completer<void>();
      when(() => cubit.uploadManifest(method: any(named: 'method')))
          .thenAnswer((_) => gate.future);
      await pumpReview(tester, names: names);
      tester.takeException();

      bool held() => find
          .ancestor(
            of: find.byType(ArNSFlowNameSection),
            matching: find.byType(AbsorbPointer),
          )
          .evaluate()
          .any((e) => (e.widget as AbsorbPointer).absorbing);

      expect(held(), isFalse);
      tester
          .widget<ArDriveButtonNew>(primary('Create deployment'))
          .onPressed!();
      await tester.pump();
      expect(held(), isTrue, reason: 'what was approved is what is applied');

      gate.complete();
      await tester.pump();
      tester.takeException();
      expect(held(), isFalse);
    });

    testWidgets(
        'a new version waits for the names it moves, then offers Create',
        (tester) async {
      ready = true;
      final lookup = Completer<List<ArNSNameRecord>>();
      await pumpReview(
        tester,
        names: names,
        existingManifestFileId: 'old-file',
        lookupFollowing: (_) => lookup.future,
      );
      tester.takeException();

      expect(
        tester
            .widget<ArDriveButtonNew>(primary('Create deployment'))
            .isDisabled,
        isTrue,
        reason: 'which names move is not known yet',
      );

      lookup.complete(const []);
      await tester.pump();
      await tester.pump();
      tester.takeException();

      verify(() => names.setFollowing(any())).called(1);
      expect(
        tester
            .widget<ArDriveButtonNew>(primary('Create deployment'))
            .isDisabled,
        isFalse,
      );
    });

    testWidgets('a names lookup that fails does not leave Create off',
        (tester) async {
      ready = true;
      await pumpReview(
        tester,
        names: names,
        existingManifestFileId: 'old-file',
        lookupFollowing: (_) async => throw Exception('db'),
      );
      await tester.pump();
      await tester.pump();
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
