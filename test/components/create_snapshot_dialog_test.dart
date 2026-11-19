import 'dart:async';

import 'package:ardrive/blocs/create_snapshot/create_snapshot_cubit.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/components/create_snapshot_dialog.dart';
import 'package:ardrive/components/upload_review_dialog.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/models/models.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../test_utils/utils.dart';

class _MockCreateSnapshotCubit extends MockCubit<CreateSnapshotState>
    implements CreateSnapshotCubit {}

/// The snapshot dialog: opening it starts the work, and the one screen it
/// ends on holds the explanation, the size and the cost, with one name for
/// the action. Failure and a short balance say what to do next.
void main() {
  final drive = Drive(
    id: 'drive-id',
    rootFolderId: 'root',
    ownerAddress: 'owner',
    name: 'My Drive',
    privacy: 'public',
    lastBlockHeight: 0,
    isHidden: false,
    dateCreated: DateTime(2024),
    lastUpdated: DateTime(2024),
  );

  late _MockCreateSnapshotCubit cubit;

  setUpAll(() => registerFallbackValue(const SelectedDrive(driveId: null)));

  setUp(() {
    cubit = _MockCreateSnapshotCubit();
    when(() =>
            cubit.confirmDriveAndHeighRange(any(), range: any(named: 'range')))
        .thenAnswer((_) async {});
    when(() => cubit.confirmSnapshotCreation()).thenAnswer((_) async {});
    when(() => cubit.cancelSnapshotCreation()).thenAnswer((_) async {});
    when(() => cubit.refreshTurboBalance()).thenAnswer((_) async {});
  });

  Future<void> pumpDialog(
    WidgetTester tester,
    CreateSnapshotState state,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    whenListen(
      cubit,
      const Stream<CreateSnapshotState>.empty(),
      initialState: state,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ActivityTracker(),
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
              body: BlocProvider<CreateSnapshotCubit>.value(
                value: cubit,
                child: CreateSnapshotDialog(
                  drive: drive,
                  promptToSnapshotBloc: MockPromptToSnapshotBloc(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  ConfirmingSnapshotCreation confirming() => ConfirmingSnapshotCreation(
        snapshotSize: 2048,
        costEstimateAr: UploadCostEstimate.zero(),
        costEstimateTurbo: UploadCostEstimate.zero(),
        hasNoTurboBalance: false,
        isTurboUploadPossible: true,
        arBalance: '1',
        turboCredits: '1',
        uploadMethod: UploadMethod.turbo,
        isButtonToUploadEnabled: true,
        sufficientBalanceToPayWithAr: true,
        sufficientBalanceToPayWithTurbo: true,
        freeStatus: FreeUploadStatus.free,
      );

  /// A paid snapshot: [balance] winston credits against a price of 3 billion.
  ConfirmingSnapshotCreation paid({BigInt? balance}) =>
      ConfirmingSnapshotCreation(
        snapshotSize: 2048,
        costEstimateAr: UploadCostEstimate(
          pstFee: BigInt.zero,
          totalCost: BigInt.from(4000000000),
          totalSize: 2048,
          usdUploadCost: null,
        ),
        costEstimateTurbo: UploadCostEstimate(
          pstFee: BigInt.zero,
          totalCost: BigInt.from(3000000000),
          totalSize: 2048,
          usdUploadCost: 0.31,
        ),
        hasNoTurboBalance: false,
        isTurboUploadPossible: true,
        arBalance: '0',
        turboCredits: '1',
        turboBalance: balance ?? BigInt.from(5000000000),
        uploadMethod: UploadMethod.turbo,
        isButtonToUploadEnabled: true,
        sufficientBalanceToPayWithAr: false,
        sufficientBalanceToPayWithTurbo: true,
        freeStatus: FreeUploadStatus.notEligible,
      );

  List<String> buttons(WidgetTester tester) => tester
      .widgetList<ArDriveButtonNew>(find.byType(ArDriveButtonNew))
      .map((b) => b.text)
      .toList();

  testWidgets('opening it starts the work: no screen that only explains',
      (tester) async {
    await pumpDialog(tester, CreateSnapshotInitial());

    verify(() => cubit.confirmDriveAndHeighRange('drive-id')).called(1);
    expect(find.text('Preparing snapshot'), findsOneWidget);
    expect(find.text('Create snapshot'), findsNothing,
        reason: 'nothing to confirm until the size and cost are known');
    expect(find.text('New snapshot'), findsNothing);
  });

  testWidgets('it does not start the work twice for a dialog already past it',
      (tester) async {
    await pumpDialog(tester, confirming());

    verifyNever(() => cubit.confirmDriveAndHeighRange(any()));
  });

  testWidgets('the one screen explains, sizes and creates, by one name',
      (tester) async {
    await pumpDialog(tester, confirming());

    expect(find.text('Create snapshot'), findsNWidgets(2),
        reason: 'the title and the action');
    expect(find.textContaining('makes My Drive load faster'), findsOneWidget);
    expect(find.text('2 KiB'), findsOneWidget,
        reason: 'its row carries the size');
    expect(find.text('Upload snapshot'), findsNothing);
    expect(buttons(tester), ['Cancel', 'Create snapshot']);

    await tester.tap(find.widgetWithText(ArDriveButtonNew, 'Create snapshot'));
    await tester.pump();

    verify(() => cubit.confirmSnapshotCreation()).called(1);
  });

  testWidgets('a failure lists Close then Try again, the retry primary',
      (tester) async {
    await pumpDialog(tester, SnapshotUploadFailure());

    expect(find.byType(ArDriveNotice), findsOneWidget);
    expect(buttons(tester), ['Close', 'Try again']);
    expect(find.text('OK'), findsNothing);

    await tester.tap(find.widgetWithText(ArDriveButtonNew, 'Try again'));
    await tester.pump();

    verify(() => cubit.confirmDriveAndHeighRange('drive-id')).called(1);
  });

  testWidgets('an AR send that may have posted names it and offers no retry',
      (tester) async {
    await pumpDialog(tester, SnapshotUploadFailure(postedTxId: 'tx-maybe'));

    expect(find.textContaining('tx-maybe'), findsOneWidget);
    expect(buttons(tester), ['Close']);
  });

  testWidgets('a payment the Turbo account cannot make stays in the dialog',
      (tester) async {
    await pumpDialog(tester, SnapshotUploadFailure(isPaymentError: true));

    expect(find.text('Free allowance used up'), findsOneWidget);
    expect(buttons(tester), ['Close', 'Buy credits']);
    expect(find.byType(CreateSnapshotDialog), findsOneWidget);
  });

  testWidgets('success is named for what happened, with a Close',
      (tester) async {
    await pumpDialog(tester, SnapshotUploadSuccess());

    expect(find.text('Snapshot created'), findsOneWidget);
    expect(find.text('Success'), findsNothing);
    expect(buttons(tester), ['Close']);
  });

  testWidgets('Done tells the suggestion a snapshot was made', (tester) async {
    final bloc = MockPromptToSnapshotBloc();
    whenListen(
      cubit,
      Stream<CreateSnapshotState>.value(SnapshotUploadSuccess()),
      initialState: CreateSnapshotInitial(),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ActivityTracker(),
        child: ArDriveTheme(
          themeData: lightTheme(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: BlocProvider<CreateSnapshotCubit>.value(
              value: cubit,
              child: CreateSnapshotDialog(
                drive: drive,
                promptToSnapshotBloc: bloc,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    verify(() => bloc.add(any(that: isA<DriveSnapshotted>()))).called(1);
  });

  testWidgets('two fast presses of Create snapshot make one call',
      (tester) async {
    final gate = Completer<void>();
    when(() => cubit.confirmSnapshotCreation()).thenAnswer((_) => gate.future);
    await pumpDialog(tester, confirming());

    final create = find.widgetWithText(ArDriveButtonNew, 'Create snapshot');
    tester.widget<ArDriveButtonNew>(create).onPressed!();
    tester.widget<ArDriveButtonNew>(create).onPressed!();
    await tester.pump();

    verify(() => cubit.confirmSnapshotCreation()).called(1);
    gate.complete();
    await tester.pump();
  });

  testWidgets('two fast presses of Try again make one call', (tester) async {
    final gate = Completer<void>();
    when(() =>
            cubit.confirmDriveAndHeighRange(any(), range: any(named: 'range')))
        .thenAnswer((_) => gate.future);
    await pumpDialog(tester, SnapshotUploadFailure());

    final retry = find.widgetWithText(ArDriveButtonNew, 'Try again');
    tester.widget<ArDriveButtonNew>(retry).onPressed!();
    tester.widget<ArDriveButtonNew>(retry).onPressed!();
    await tester.pump();

    verify(() => cubit.confirmDriveAndHeighRange('drive-id')).called(1);
    gate.complete();
    await tester.pump();
  });

  testWidgets('free: the upload review\'s cost block says Free',
      (tester) async {
    await pumpDialog(tester, confirming());

    expect(find.byType(UploadCostBlock), findsOneWidget);
    expect(find.text('Cost'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Covered by your free upload allowance'), findsOneWidget);
  });

  testWidgets('paid with credits: the cost in dollars, and Create snapshot',
      (tester) async {
    await pumpDialog(tester, paid());

    expect(find.byType(UploadCostBlock), findsOneWidget);
    expect(find.textContaining(r'$0.31', findRichText: true), findsOneWidget);
    expect(find.text('Free'), findsNothing);
    expect(buttons(tester), ['Cancel', 'Create snapshot']);

    await tester.tap(find.widgetWithText(ArDriveButtonNew, 'Create snapshot'));
    await tester.pump();

    verify(() => cubit.setUploadMethod(UploadMethod.turbo)).called(1);
    verify(() => cubit.confirmSnapshotCreation()).called(1);
  });

  testWidgets('short of credits: Add credits, never Create snapshot',
      (tester) async {
    await pumpDialog(tester, paid(balance: BigInt.zero));

    expect(find.byType(UploadCostBlock), findsOneWidget);
    expect(buttons(tester), ['Cancel', 'Add credits']);
    verifyNever(() => cubit.confirmSnapshotCreation());
  });

  testWidgets('Create snapshot is busy from the press, and Cancel waits',
      (tester) async {
    final gate = Completer<void>();
    when(() => cubit.confirmSnapshotCreation()).thenAnswer((_) => gate.future);
    await pumpDialog(tester, confirming());

    tester
        .widget<ArDriveButtonNew>(
            find.widgetWithText(ArDriveButtonNew, 'Create snapshot'))
        .onPressed!();
    await tester.pump();

    expect(find.byType(ArDriveSpinner), findsOneWidget);
    final cancel = tester.widget<ArDriveButtonNew>(
        find.widgetWithText(ArDriveButtonNew, 'Cancel'));
    expect(cancel.isDisabled, isTrue);

    gate.complete();
    await tester.pump();
  });

  ConfirmingSnapshotCreation walletCanPay({
    bool turboPrice = true,
    bool unreachable = false,
  }) =>
      ConfirmingSnapshotCreation(
        snapshotSize: 2048,
        costEstimateAr: UploadCostEstimate(
          pstFee: BigInt.zero,
          totalCost: BigInt.from(4000000000),
          totalSize: 2048,
          usdUploadCost: null,
        ),
        costEstimateTurbo: turboPrice
            ? UploadCostEstimate(
                pstFee: BigInt.zero,
                totalCost: BigInt.from(3000000000),
                totalSize: 2048,
                usdUploadCost: 0.31,
              )
            : UploadCostEstimate.zero(),
        hasNoTurboBalance: false,
        isTurboUploadPossible: true,
        arBalance: '1',
        turboCredits: '1',
        turboBalance: BigInt.from(5000000000),
        turboUnreachable: unreachable,
        // The cubit opens on the wallet; the review does not take that as a
        // choice.
        uploadMethod: UploadMethod.ar,
        isButtonToUploadEnabled: true,
        sufficientBalanceToPayWithAr: true,
        sufficientBalanceToPayWithTurbo: true,
        freeStatus: FreeUploadStatus.notEligible,
      );

  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 1));

  testWidgets('the cubit opening on the wallet still shows Turbo Credits',
      (tester) async {
    await pumpDialog(tester, walletCanPay());
    await settle(tester);

    expect(find.textContaining(r'$0.31', findRichText: true), findsOneWidget);
    tester
        .widget<ArDriveButtonNew>(
            find.widgetWithText(ArDriveButtonNew, 'Create snapshot'))
        .onPressed!();
    await tester.pump();

    verify(() => cubit.setUploadMethod(UploadMethod.turbo)).called(1);
  });

  testWidgets('the wallet is used only when picked, then Create pays with it',
      (tester) async {
    await pumpDialog(tester, walletCanPay());
    await settle(tester);

    await tester.ensureVisible(find.text('Wallet (AR)'));
    await tester.tap(find.text('Wallet (AR)'));
    await tester.pump();
    verify(() => cubit.setUploadMethod(UploadMethod.ar)).called(1);
    tester
        .widget<ArDriveButtonNew>(
            find.widgetWithText(ArDriveButtonNew, 'Create snapshot'))
        .onPressed!();
    await tester.pump();

    verify(() => cubit.setUploadMethod(UploadMethod.ar)).called(1);
    verify(() => cubit.confirmSnapshotCreation()).called(1);
  });

  testWidgets('no Turbo price: the wallet-only review, Create pays with it',
      (tester) async {
    await pumpDialog(tester, walletCanPay(turboPrice: false));
    await settle(tester);

    expect(find.byType(UploadCostBlock), findsOneWidget);
    expect(buttons(tester), ['Cancel', 'Create snapshot']);
    tester
        .widget<ArDriveButtonNew>(
            find.widgetWithText(ArDriveButtonNew, 'Create snapshot'))
        .onPressed!();
    await tester.pump();

    verify(() => cubit.setUploadMethod(UploadMethod.ar)).called(1);
    verify(() => cubit.confirmSnapshotCreation()).called(1);
  });

  testWidgets('a balance that could not be read: Try again, not a payment',
      (tester) async {
    await pumpDialog(tester, walletCanPay(unreachable: true));
    await settle(tester);

    expect(find.byType(UploadCostBlock), findsNothing);
    expect(buttons(tester), ['Try again', 'Cancel']);
    await tester.ensureVisible(find.text('Try again'));
    await tester.tap(find.text('Try again'));
    await tester.pump();

    verify(() => cubit.refreshTurboBalance()).called(1);
    verifyNever(() => cubit.confirmSnapshotCreation());
  });
}
