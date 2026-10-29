import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/models/upload_review_summary.dart';
import 'package:ardrive/components/fs_entry_license_form.dart';
import 'package:ardrive/services/license/license.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

class _MockLicenseBloc
    extends MockBloc<FsEntryLicenseEvent, FsEntryLicenseState>
    implements FsEntryLicenseBloc {}

/// The ends of the licensing flow. They were hand-made cards with a close
/// cross and an inverted button; now they are standard dialogs.
void main() {
  late _MockLicenseBloc bloc;

  setUpAll(() => registerFallbackValue(const FsEntryLicenseFailureTryAgain()));

  setUp(() {
    bloc = _MockLicenseBloc();
    when(() => bloc.selectedLicenseMeta).thenReturn(udlLicenseMeta);
  });

  Future<void> pump(WidgetTester tester, FsEntryLicenseState state) async {
    when(() => bloc.state).thenReturn(state);
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<FsEntryLicenseBloc>.value(value: bloc),
                BlocProvider<DriveDetailCubit>.value(
                    value: MockDriveDetailCubit()),
              ],
              child: const FsEntryLicenseForm(selectedItems: []),
            ),
          ),
        ),
      ),
    );
  }

  List<(String, ButtonVariant)> actions(WidgetTester tester) => tester
      .widgetList<ArDriveButtonNew>(find.byType(ArDriveButtonNew))
      .map((b) => (b.text, b.variant))
      .toList();

  testWidgets('no file to license is a standard dialog with a quiet Close',
      (tester) async {
    await pump(tester, const FsEntryLicenseNoFiles());

    expect(find.byType(ArDriveStandardModalNew), findsOneWidget);
    expect(find.text('No valid file to license.'), findsOneWidget);
    expect(actions(tester), [('Close', ButtonVariant.secondary)]);
  });

  testWidgets('success says so in a standard dialog', (tester) async {
    await pump(tester, const FsEntryLicenseSuccess());

    expect(find.byType(ArDriveStandardModalNew), findsOneWidget);
    expect(find.text('You little licenser, you.'), findsOneWidget);
    expect(actions(tester), [('Close', ButtonVariant.secondary)]);
  });

  testWidgets('a failure offers to try again as the main action',
      (tester) async {
    await pump(tester, const FsEntryLicenseFailure());

    expect(actions(tester), [
      ('Close', ButtonVariant.secondary),
      ('Try again', ButtonVariant.primary),
    ]);

    await tester.tap(find.text('Try again'));
    verify(() => bloc.add(const FsEntryLicenseFailureTryAgain())).called(1);
  });

  group('the review states the cost of the license', () {
    setUp(() {
      when(() => bloc.filesToLicense).thenReturn([]);
      when(() => bloc.licenseParams).thenReturn(null);
    });

    UploadReviewSummary summary({
      bool isFree = false,
      bool isCovered = false,
      bool priceUnavailable = false,
    }) =>
        UploadReviewSummary(
          method: UploadMethod.turbo,
          isFree: isFree,
          priceUnavailable: priceUnavailable,
          isCovered: isCovered,
          overFreeAllowance: !isFree,
          offersPaymentChoice: false,
          usesLegacySelector: false,
          creditsCost: BigInt.from(40000000),
          creditsBalance:
              isCovered ? BigInt.from(10).pow(12) : BigInt.from(10000000),
          usdCost: 0.0002,
          arCost: BigInt.zero,
        );

    testWidgets('no made-up cost while it is read, and no Confirm',
        (tester) async {
      await pump(tester, const FsEntryLicenseReviewing());

      expect(find.textContaining('0 AR'), findsNothing);
      expect(find.textContaining('Free for now'), findsNothing);
      final confirm = tester.widget<ArDriveButtonNew>(
          find.widgetWithText(ArDriveButtonNew, 'Confirm'));
      expect(confirm.isDisabled, isTrue);
    });

    testWidgets('free under the free upload allowance', (tester) async {
      await pump(
          tester,
          FsEntryLicenseReviewing(
              summary: summary(isFree: true, isCovered: true)));

      expect(find.text('Free'), findsOneWidget);
      expect(
          find.text(
              'Covered by your free upload allowance. Saved for good, paid once.'),
          findsOneWidget);
      expect(actions(tester).last, ('Confirm', ButtonVariant.primary));

      await tester.tap(find.text('Confirm'));
      verify(() => bloc.add(const FsEntryLicenseReviewConfirm())).called(1);
    });

    testWidgets('priced in Turbo Credits, with the dollar figure',
        (tester) async {
      await pump(
          tester, FsEntryLicenseReviewing(summary: summary(isCovered: true)));

      expect(find.textContaining('< \$0.01'), findsOneWidget);
      expect(
          find.text(
              'Paid once with Turbo Credits. Saved for good, no subscription.'),
          findsOneWidget);
      expect(actions(tester).last, ('Confirm', ButtonVariant.primary));
    });

    testWidgets('not covered: says so, and offers Add credits, not Confirm',
        (tester) async {
      await pump(tester, FsEntryLicenseReviewing(summary: summary()));

      expect(
          find.textContaining(
              'This change is over your free upload allowance.'),
          findsOneWidget);
      expect(
          find.textContaining('Add Turbo Credits to save it.'), findsOneWidget);
      expect(find.text('Confirm'), findsNothing);
      expect(actions(tester).last, ('Add credits', ButtonVariant.primary));

      await tester.tap(find.text('Add credits'));
      await tester.pumpAndSettle();
      expect(find.text('Add Turbo Credits'), findsOneWidget);
    });

    testWidgets('no price: says so, Try again reads it again, and no Confirm',
        (tester) async {
      await pump(tester,
          FsEntryLicenseReviewing(summary: summary(priceUnavailable: true)));

      expect(
          find.text(
              "Couldn't get a price. Check your connection and try again."),
          findsOneWidget);
      expect(find.text('Confirm'), findsNothing);

      await tester.tap(find.text('Try again'));
      verify(() => bloc.add(const FsEntryLicenseCostRefresh())).called(1);
    });

    testWidgets('Back goes to the step before', (tester) async {
      await pump(
          tester,
          FsEntryLicenseReviewing(
              summary: summary(isFree: true, isCovered: true)));

      await tester.tap(find.text('Back'));
      verify(() => bloc.add(const FsEntryLicenseReviewBack())).called(1);
    });
  });
}
