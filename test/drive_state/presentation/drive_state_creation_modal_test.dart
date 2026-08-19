import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/components/payment_method_selector_widget.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_entity.dart';
import 'package:ardrive/drive_state/domain/drive_state_publish_cost.dart';
import 'package:ardrive/drive_state/presentation/drive_state_creation_cubit/drive_state_creation_cubit.dart';
import 'package:ardrive/drive_state/presentation/drive_state_creation_modal.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

/// The confirmation surface. Three things are worth a widget test here: that
/// the user is told what would be published *and what it costs* before they
/// can agree to it, that a refusal offers no way past itself, and that a
/// confirm button which cannot be paid for does not work.
void main() {
  late _MockCubit cubit;

  setUp(() => cubit = _MockCubit());

  Widget wrap(DriveStateCreationState state) {
    when(() => cubit.state).thenReturn(state);
    whenListen(cubit, const Stream<DriveStateCreationState>.empty());

    return ArDriveTheme(
      themeData: lightTheme(),
      child: MaterialApp(
        // The reused payment components carry their own localisation, unlike
        // the strings this modal writes itself.
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', '')],
        home: Scaffold(
          body: BlocProvider<DriveStateCreationCubit>.value(
            value: cubit,
            child: const DriveStateCreationModal(driveName: 'My Drive'),
          ),
        ),
      ),
    );
  }

  PreparedDriveStateArtifact artifact() => PreparedDriveStateArtifact(
        entity: DriveStateEntity(
          id: 'artifact-id',
          driveId: 'drive-id',
          blockEnd: 1814228,
          dataStart: 0,
          dataEnd: 1814228,
          entityCount: 12,
          cipher: 'AES256-GCM',
          cipherIv: 'aXY=',
        ),
        driveId: 'drive-id',
        driveName: 'My Drive',
        entityCount: 12,
        sizeInBytes: 6979321,
      );

  DriveStatePublishCost cost({
    BigInt? arCost,
    BigInt? turboCost,
    bool sufficientArBalance = true,
    bool sufficientTurboBalance = true,
    bool isTurboUploadPossible = true,
    FreeUploadStatus freeStatus = FreeUploadStatus.notEligible,
  }) =>
      DriveStatePublishCost(
        costEstimateAr: UploadCostEstimate(
          pstFee: BigInt.zero,
          totalCost: arCost ?? BigInt.from(4000000000),
          totalSize: 6979321,
          usdUploadCost: 0.42,
        ),
        costEstimateTurbo: UploadCostEstimate(
          pstFee: BigInt.zero,
          totalCost: turboCost ?? BigInt.from(3000000000),
          totalSize: 6979321,
          usdUploadCost: 0.31,
        ),
        isTurboUploadPossible: isTurboUploadPossible,
        hasNoTurboBalance: false,
        arBalance: '1.5',
        turboCredits: '2.5',
        sufficientArBalance: sufficientArBalance,
        sufficientTurboBalance: sufficientTurboBalance,
        freeStatus: freeStatus,
      );

  DriveStateCreationReady ready({
    DriveStatePublishCost? withCost,
    UploadMethod method = UploadMethod.turbo,
  }) =>
      DriveStateCreationReady(
        artifact: artifact(),
        cost: withCost ?? cost(),
        method: method,
      );

  ArDriveButtonNew publishButton(WidgetTester tester) =>
      tester.widget<ArDriveButtonNew>(
        find.widgetWithText(ArDriveButtonNew, 'Publish'),
      );

  testWidgets('the confirmation shows what would be published', (tester) async {
    await tester.pumpWidget(wrap(ready()));
    await tester.pumpAndSettle();

    expect(find.text('My Drive'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('6.66 MiB'), findsOneWidget);
    expect(find.text('0 to 1814228'), findsOneWidget);
    expect(find.textContaining('permanent'), findsOneWidget);
    expect(
        find.textContaining('Nothing has been uploaded yet'), findsOneWidget);
  });

  testWidgets('the confirmation shows what it costs, in the selected method',
      (tester) async {
    await tester.pumpWidget(wrap(ready()));
    await tester.pumpAndSettle();

    expect(find.text('0.003 Credits'), findsOneWidget);
    expect(find.textContaining('Turbo Balance: 2.5 Credits'), findsOneWidget);
  });

  testWidgets('switching to AR shows the AR price instead', (tester) async {
    await tester.pumpWidget(wrap(ready(method: UploadMethod.ar)));
    await tester.pumpAndSettle();

    expect(find.text('0.004 AR'), findsOneWidget);
  });

  testWidgets('a free artifact says so and offers no method to pay with',
      (tester) async {
    await tester.pumpWidget(wrap(ready(
      withCost: cost(freeStatus: FreeUploadStatus.free),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Free, thanks to Turbo'), findsOneWidget);
    expect(find.byType(PaymentMethodSelector), findsNothing);
    expect(publishButton(tester).isDisabled, isFalse);
  });

  testWidgets('an artifact nobody can pay for disables the confirm button',
      (tester) async {
    await tester.pumpWidget(wrap(ready(
      withCost: cost(
        sufficientArBalance: false,
        sufficientTurboBalance: false,
      ),
    )));
    await tester.pumpAndSettle();

    expect(publishButton(tester).isDisabled, isTrue);
    expect(
      find.textContaining('cannot be published yet'),
      findsOneWidget,
    );
  });

  testWidgets('a method the user cannot afford disables the confirm button',
      (tester) async {
    await tester.pumpWidget(wrap(ready(
      withCost: cost(sufficientTurboBalance: false),
      method: UploadMethod.turbo,
    )));
    await tester.pumpAndSettle();

    expect(publishButton(tester).isDisabled, isTrue);
    // AR would still work, so the modal must not claim the artifact is
    // unpublishable — only that this method is.
    expect(find.textContaining('cannot be published yet'), findsNothing);
  });

  testWidgets('nothing is published until the user asks for it',
      (tester) async {
    await tester.pumpWidget(wrap(ready()));
    await tester.pumpAndSettle();

    when(() => cubit.publish()).thenAnswer((_) async {});

    verifyNever(() => cubit.publish());

    // The button's own callback, invoked directly: this asserts what the
    // confirm action is wired to, without depending on where in a modal's
    // layout the button lands under a test-sized viewport.
    publishButton(tester).onPressed!();
    await tester.pump();

    verify(() => cubit.publish()).called(1);
  });

  testWidgets('a refusal explains itself and offers no way past it',
      (tester) async {
    await tester.pumpWidget(wrap(DriveStateCreationRefused(
      refusal: DriveStateCreationRefusal.syncSkippedEntities,
      reason: 'The last sync of this drive could not read 3 items.',
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('could not read 3 items'), findsOneWidget);
    expect(find.textContaining('would record the gap forever'), findsOneWidget);
    expect(find.text('Publish'), findsNothing);
    verifyNever(() => cubit.publish());
  });

  testWidgets('a failed publish shows the uploader\'s own sentence',
      (tester) async {
    await tester.pumpWidget(wrap(DriveStateCreationFailure(
      'Turbo declined the payment for this artifact.',
    )));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Turbo declined the payment'),
      findsOneWidget,
    );
    expect(find.text('Publish'), findsNothing);
  });

  testWidgets('a price that could not be established is not a confirm button',
      (tester) async {
    await tester.pumpWidget(wrap(DriveStateCreationFailure(
      'The cost of publishing could not be determined, so nothing is being '
      'offered for confirmation.',
    )));
    await tester.pumpAndSettle();

    expect(find.text('Publish'), findsNothing);
    verifyNever(() => cubit.publish());
  });
}

class _MockCubit extends MockCubit<DriveStateCreationState>
    implements DriveStateCreationCubit {}
