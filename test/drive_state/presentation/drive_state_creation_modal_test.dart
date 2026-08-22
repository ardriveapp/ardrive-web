import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/components/payment_method_selector_widget.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_entity.dart';
import 'package:ardrive/drive_state/domain/drive_state_publish_cost.dart';
import 'package:ardrive/drive_state/presentation/drive_state_creation_cubit/drive_state_creation_cubit.dart';
import 'package:ardrive/drive_state/presentation/drive_state_creation_modal.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

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

  PreparedDriveStateArtifact artifact({
    String driveName = 'My Drive',
    int entityCount = 12,
    int blockEnd = 1814228,
    bool isEncrypted = true,
  }) =>
      PreparedDriveStateArtifact(
        entity: DriveStateEntity(
          id: 'artifact-id',
          driveId: 'drive-id',
          blockEnd: blockEnd,
          dataStart: 0,
          dataEnd: blockEnd,
          entityCount: entityCount,
          cipher: isEncrypted ? 'AES256-GCM' : null,
          cipherIv: isEncrypted ? 'aXY=' : null,
        ),
        driveId: 'drive-id',
        driveName: driveName,
        entityCount: entityCount,
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
    PreparedDriveStateArtifact? withArtifact,
    UploadMethod method = UploadMethod.turbo,
  }) =>
      DriveStateCreationReady(
        artifact: withArtifact ?? artifact(),
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

  /// A public drive's confirmation is the private one minus one clause.
  ///
  /// The encryption clause is dropped because it would be false, and nothing
  /// takes its place. A public drive is public because its owner chose that,
  /// so a line at confirmation time telling them public things are readable
  /// would be telling them what they decided — and snapshots have published
  /// the same enumeration for public drives for years without saying anything,
  /// so singling out the artifact would imply a difference that does not
  /// exist. The user is confirming a spend, and what they need for that is the
  /// drive, the count, the size, the range and the price.
  testWidgets(
      'a public drive is shown the same thing, minus the encryption '
      'clause', (tester) async {
    await tester.pumpWidget(
      wrap(ready(withArtifact: artifact(isEncrypted: false))),
    );
    await tester.pumpAndSettle();

    // Everything the private drive is shown.
    expect(find.text('My Drive'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('6.66 MiB'), findsOneWidget);
    expect(find.text('0 to 1814228'), findsOneWidget);
    expect(find.textContaining('permanent'), findsOneWidget);
    expect(
        find.textContaining('Nothing has been uploaded yet'), findsOneWidget);
    expect(find.text('Publish'), findsOneWidget);

    // And not the one thing that would be untrue.
    expect(find.textContaining('encrypted with your drive key'), findsNothing);
  });

  testWidgets('a private drive is told its artifact is encrypted',
      (tester) async {
    await tester.pumpWidget(wrap(ready()));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('encrypted with your drive key'),
      findsOneWidget,
    );
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

  /// The same modal, on the screens it actually ships to.
  ///
  /// These pump through [showArDriveDialog] rather than dropping the modal
  /// into a `Scaffold` body, because the geometry a phone breaks on is the
  /// geometry the dialog decides. And what it decides is not what a reading of
  /// `Dialog` suggests: `showAnimatedDialog` passes `insetPadding` explicitly
  /// — `null` above 600 logical pixels of height, an explicit zero below it —
  /// and `Dialog` reads a null `insetPadding` as [EdgeInsets.zero] rather than
  /// falling back to its 40-pixel default. So the dialog reserves *no*
  /// horizontal margin at any size, and [modalStandardMaxWidthSize] is the
  /// only thing standing between this modal and the edge of the screen. That
  /// is measured, not assumed: with a fixed `width:` reintroduced, the modal
  /// renders 390 wide on a 390-wide phone.
  ///
  /// Every one of these asserts [WidgetTester.takeException] is null. A
  /// `RenderFlex overflowed` is reported through `FlutterError.onError`
  /// during paint, so it would fail these tests anyway — the explicit check
  /// is there to name the failure rather than to create it.
  group('on the screens it ships to', () {
    // An iPhone 14: the common case, and wide enough that nothing is
    // expected to be tight.
    const phone = Size(390, 844);
    // An iPhone SE: the narrowest screen worth supporting, and short enough
    // (< 600) to take `showAnimatedDialog`'s low-screen inset path.
    const smallPhone = Size(320, 568);
    const desktop = Size(1440, 900);

    late ActivityTracker activityTracker;

    setUp(() => activityTracker = ActivityTracker());

    /// The production entry path's chrome, minus the services
    /// [promptToCreateDriveState] needs to build a real cubit.
    Future<void> openModal(
      WidgetTester tester,
      DriveStateCreationState state, {
      required Size surface,
      String driveName = 'My Drive',
    }) async {
      tester.view.physicalSize = surface;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => cubit.state).thenReturn(state);
      when(() => cubit.publish()).thenAnswer((_) async {});
      whenListen(cubit, const Stream<DriveStateCreationState>.empty());

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
            // Provided exactly as `main.dart` provides it, since
            // `showArDriveDialog` reads it out of the tree.
            home: ChangeNotifierProvider<ActivityTracker>.value(
              value: activityTracker,
              child: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showArDriveDialog(
                      context,
                      content: BlocProvider<DriveStateCreationCubit>.value(
                        value: cubit,
                        child: DriveStateCreationModal(driveName: driveName),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    /// The modal is laid out inside the screen, in both axes, with nothing
    /// clipped off an edge, and no wider than its own component's rule.
    ///
    /// `takeException` catches a `RenderFlex` that overflowed its own box;
    /// the rect catches the box itself being placed outside the viewport,
    /// which no `RenderFlex` reports.
    ///
    /// The width cap is the third check and it is not redundant. A fixed
    /// `width:` handed to [ArDriveStandardModalNew] replaces
    /// [modalStandardMaxWidthSize] in a `ConstrainedBox`'s `maxWidth`, and
    /// `BoxConstraints.enforce` quietly clamps that back down to whatever the
    /// `Dialog` left — so on a phone an overridden cap overflows nothing and
    /// is invisible to the two checks above. It is visible here, on any
    /// screen with room to honour it.
    void expectFitsOnScreen(WidgetTester tester, Size surface) {
      expect(tester.takeException(), isNull);

      final rect = tester.getRect(find.byType(ArDriveStandardModalNew));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(surface.width));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(surface.height));
      expect(rect.width, lessThanOrEqualTo(modalStandardMaxWidthSize));
    }

    for (final surface in {
      'a phone': phone,
      'a small phone': smallPhone,
      'a desktop': desktop,
    }.entries) {
      testWidgets('the confirmation is usable on ${surface.key}',
          (tester) async {
        await openModal(tester, ready(), surface: surface.value);

        expectFitsOnScreen(tester, surface.value);

        // What it costs, and the selector that decides who pays, are both
        // readable — not merely present in the tree.
        await tester.ensureVisible(find.text('0.003 Credits'));
        expect(find.byType(PaymentMethodSelector), findsOneWidget);
        await tester.ensureVisible(find.byType(PaymentMethodSelector));

        // Both actions exist...
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Publish'), findsOneWidget);

        // ...and the one that spends money can actually be reached and hit.
        // `tap` hit-tests, so a button pushed under another widget or off
        // the bottom of a short viewport fails here.
        await tester.ensureVisible(find.text('Publish'));
        await tester.tap(find.text('Publish'));
        await tester.pump();

        verify(() => cubit.publish()).called(1);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a long drive name and a large count do not overflow a phone',
        (tester) async {
      await openModal(
        tester,
        ready(
          withArtifact: artifact(
            driveName: 'Quarterly Financial Reporting And Archived '
                'Correspondence 2019-2026',
            entityCount: 1234567890,
            blockEnd: 1814228999,
          ),
        ),
        surface: smallPhone,
        driveName: 'Quarterly Financial Reporting And Archived '
            'Correspondence 2019-2026',
      );

      expectFitsOnScreen(tester, smallPhone);

      // The long values are shown in full rather than dropped, and the
      // confirm button survives them.
      expect(
          find.textContaining('Quarterly Financial Reporting'), findsOneWidget);
      expect(find.text('1234567890'), findsOneWidget);
      expect(find.text('0 to 1814228999'), findsOneWidget);

      await tester.ensureVisible(find.text('Publish'));
      await tester.tap(find.text('Publish'));
      await tester.pump();

      verify(() => cubit.publish()).called(1);
      expect(tester.takeException(), isNull);
    });

    // The refusal is the longest thing this modal ever renders — the D3 rail
    // adds a paragraph above a reason the service writes — and it is the one
    // the user cannot dismiss any other way, since it has no confirm button
    // and the barrier is the only alternative to its Close.
    testWidgets('a long refusal stays on screen and keeps its close button',
        (tester) async {
      await openModal(
        tester,
        DriveStateCreationRefused(
          refusal: DriveStateCreationRefusal.syncSkippedEntities,
          reason: 'The last sync of this drive could not read 37 items, so '
              'the drive on this device is not a complete copy of the drive '
              'on chain. Publishing its state now would record that gap in a '
              'permanent artifact that every future reader would trust. Sync '
              'this drive again, and if the same items are still missing '
              'afterwards, contact support before publishing.',
        ),
        surface: smallPhone,
      );

      expectFitsOnScreen(tester, smallPhone);

      expect(find.textContaining('could not read 37 items'), findsOneWidget);
      expect(find.text('Publish'), findsNothing);

      await tester.ensureVisible(find.text('Close'));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Reached, hit, and it dismissed the dialog.
      expect(find.byType(DriveStateCreationModal), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long failure stays on screen and keeps its close button',
        (tester) async {
      await openModal(
        tester,
        DriveStateCreationFailure(
          'The upload was rejected by every route it was offered to: Turbo '
          'returned an error for the bundled data item, and the direct '
          'gateway upload did not complete either. Nothing was published and '
          'nothing was charged. Check your connection and try again.',
        ),
        surface: smallPhone,
      );

      expectFitsOnScreen(tester, smallPhone);

      expect(find.textContaining('Nothing was published'), findsOneWidget);

      await tester.ensureVisible(find.text('Close'));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(DriveStateCreationModal), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a published artifact reports its id without overflowing',
        (tester) async {
      await openModal(
        tester,
        DriveStateCreationPublished(
          artifact: artifact(
            driveName: 'Quarterly Financial Reporting And Archived '
                'Correspondence 2019-2026',
          ),
          // A real Arweave transaction id: 43 unbroken base64url characters,
          // which is wider than a small phone's modal and has nowhere to
          // wrap.
          txId: 'PmwoP4jL1ZQVAKGSCP2NmFCiwYbnUpKMPZmKGpKQwvE',
        ),
        surface: smallPhone,
      );

      expectFitsOnScreen(tester, smallPhone);

      expect(
        find.textContaining('PmwoP4jL1ZQVAKGSCP2NmFCiwYbnUpKMPZmKGpKQwvE'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Close'));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(DriveStateCreationModal), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unaffordable artifact still fits, with its own warning',
        (tester) async {
      await openModal(
        tester,
        ready(
          withCost: cost(
            sufficientArBalance: false,
            sufficientTurboBalance: false,
          ),
        ),
        surface: smallPhone,
      );

      expectFitsOnScreen(tester, smallPhone);

      await tester.ensureVisible(find.textContaining('cannot be published'));
      await tester.ensureVisible(find.text('Publish'));
      expect(publishButton(tester).isDisabled, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}

class _MockCubit extends MockCubit<DriveStateCreationState>
    implements DriveStateCreationCubit {}
