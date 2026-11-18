import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/models/upload_review_summary.dart';
import 'package:ardrive/components/fs_entry_license_form.dart';
import 'package:ardrive/models/forms/cc.dart';
import 'package:ardrive/models/forms/udl.dart';
import 'package:ardrive/services/license/license.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:reactive_forms/reactive_forms.dart';

import '../test_utils/mocks.dart';

class _MockLicenseBloc
    extends MockBloc<FsEntryLicenseEvent, FsEntryLicenseState>
    implements FsEntryLicenseBloc {}

/// Add license, on one screen: the files, the license and its settings,
/// and the cost. It was four screens with a progress dialog on top.
void main() {
  late _MockLicenseBloc bloc;

  setUpAll(() => registerFallbackValue(const FsEntryLicenseCostRefresh()));

  setUp(() {
    bloc = _MockLicenseBloc();
    when(() => bloc.selectedLicenseMeta).thenReturn(udlLicenseMeta);
    when(() => bloc.selectedLicenseCategory).thenReturn(LicenseCategory.udl);
    when(() => bloc.categoryForm).thenReturn(FormGroup({
      'licenseCategory': FormControl<LicenseCategory>(
        validators: [Validators.required],
        value: LicenseCategory.udl,
      ),
    }));
    when(() => bloc.udlParamsForm).thenReturn(createUdlParamsForm());
    when(() => bloc.ccTypeForm).thenReturn(createCcTypeForm());
    when(() => bloc.filesToLicense).thenReturn([]);
    when(() => bloc.licenseParams).thenReturn(null);
  });

  Future<void> pump(WidgetTester tester, FsEntryLicenseState state) async {
    when(() => bloc.state).thenReturn(state);
    // One screen now holds the license's settings too: room for all of it.
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    expect(find.text('No file to license'), findsOneWidget);
    expect(actions(tester), [('Close', ButtonVariant.secondary)]);
  });

  testWidgets('success says so in a standard dialog', (tester) async {
    await pump(tester, const FsEntryLicenseSuccess());

    expect(find.byType(ArDriveStandardModalNew), findsOneWidget);
    expect(find.text('License added'), findsOneWidget);
    expect(find.text('UDL is now on 0 files.'), findsOneWidget);
    expect(actions(tester), [('Close', ButtonVariant.secondary)]);
  });

  group('the review states the cost of the license', () {
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
          find.widgetWithText(ArDriveButtonNew, 'Add license'));
      expect(confirm.isDisabled, isTrue);
    });

    testWidgets('free under the free upload allowance', (tester) async {
      await pump(
          tester,
          FsEntryLicenseReviewing(
              summary: summary(isFree: true, isCovered: true)));

      expect(find.text('Free'), findsOneWidget);
      expect(
          find.text('Covered by your free upload allowance'), findsOneWidget);
      expect(actions(tester).last, ('Add license', ButtonVariant.primary));

      await tester.tap(find.widgetWithText(ArDriveButtonNew, 'Add license'));
      verify(() => bloc.add(const FsEntryLicenseReviewConfirm())).called(1);
    });

    testWidgets('priced in Turbo Credits, with the dollar figure',
        (tester) async {
      await pump(
          tester, FsEntryLicenseReviewing(summary: summary(isCovered: true)));

      expect(find.textContaining('< \$0.01'), findsOneWidget);
      expect(find.text('Paid with Turbo Credits'), findsOneWidget);
      expect(actions(tester).last, ('Add license', ButtonVariant.primary));
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
      expect(
          find.widgetWithText(ArDriveButtonNew, 'Add license'), findsNothing);
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
      expect(
          find.widgetWithText(ArDriveButtonNew, 'Add license'), findsNothing);

      await tester.ensureVisible(find.text('Try again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Try again'));
      verify(() => bloc.add(const FsEntryLicenseCostRefresh())).called(1);
    });

    testWidgets('no price for another reason: does not blame the connection',
        (tester) async {
      await pump(
          tester,
          FsEntryLicenseReviewing(
            summary: summary(priceUnavailable: true),
            pricingFailed: true,
          ));

      expect(find.text("Couldn't get a price. Try again."), findsOneWidget);
      expect(find.textContaining('connection'), findsNothing);
      expect(
          find.widgetWithText(ArDriveButtonNew, 'Add license'), findsNothing);
    });

    testWidgets('paid from a wallet that is short: says so', (tester) async {
      await pump(
        tester,
        FsEntryLicenseReviewing(
          summary: UploadReviewSummary(
            method: UploadMethod.ar,
            isFree: false,
            priceUnavailable: false,
            isCovered: false,
            overFreeAllowance: false,
            offersPaymentChoice: false,
            usesLegacySelector: true,
            creditsCost: BigInt.zero,
            creditsBalance: BigInt.zero,
            usdCost: null,
            arCost: BigInt.from(1000000000),
          ),
        ),
      );

      expect(find.text("Your wallet doesn't have enough AR for this change."),
          findsOneWidget);
      final confirm = tester.widget<ArDriveButtonNew>(
          find.widgetWithText(ArDriveButtonNew, 'Add license'));
      expect(confirm.isDisabled, isTrue);
    });

    testWidgets(
        'one screen: the license and its settings, the cost, Cancel and '
        'Add license', (tester) async {
      await pump(
          tester,
          FsEntryLicenseReviewing(
              summary: summary(isFree: true, isCovered: true)));

      expect(find.text('License'), findsOneWidget);
      expect(find.text('License fee'), findsOneWidget);
      expect(find.text('Commercial use'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
      expect(find.text('Back'), findsNothing);
      expect(actions(tester), [
        ('Cancel', ButtonVariant.secondary),
        ('Add license', ButtonVariant.primary),
      ]);
    });

    testWidgets('a Creative Commons license with no type: no cost, no Add',
        (tester) async {
      when(() => bloc.selectedLicenseCategory).thenReturn(LicenseCategory.cc);
      await pump(tester, const FsEntryLicenseReviewing(incomplete: true));

      expect(
          find.text('Choose a license type to see the cost'), findsOneWidget);
      expect(find.byType(ArDriveSpinner), findsNothing);
      final add = tester.widget<ArDriveButtonNew>(
          find.widgetWithText(ArDriveButtonNew, 'Add license'));
      expect(add.isDisabled, isTrue);
    });

    testWidgets('while it writes: Add license busy, Cancel held, in place',
        (tester) async {
      await pump(
          tester,
          FsEntryLicenseReviewing(
              summary: summary(isFree: true, isCovered: true), busy: true));

      expect(find.byType(ArDriveStandardModalNew), findsOneWidget);
      final cancel = tester.widget<ArDriveButtonNew>(
          find.widgetWithText(ArDriveButtonNew, 'Cancel'));
      expect(cancel.isDisabled, isTrue);
      expect(find.byType(ArDriveSpinner), findsOneWidget);
    });

    testWidgets(
        'a change on screen holds Add license until it is applied, so it '
        'never writes the license from before', (tester) async {
      final category = bloc.categoryForm;
      await pump(
          tester,
          FsEntryLicenseReviewing(
              summary: summary(isFree: true, isCovered: true)));
      ArDriveButtonNew add() => tester.widget<ArDriveButtonNew>(
          find.widgetWithText(ArDriveButtonNew, 'Add license'));
      expect(add().isDisabled, isFalse);

      category.control('licenseCategory').value = LicenseCategory.cc;
      await tester.pump();
      expect(add().isDisabled, isTrue);
      verifyNever(() => bloc.add(const FsEntryLicenseSettingsChanged()));

      await tester.pump(const Duration(milliseconds: 350));
      verify(() => bloc.add(const FsEntryLicenseSettingsChanged())).called(1);
    });

    testWidgets('while it writes, the settings take no input, keys included',
        (tester) async {
      await pump(
          tester,
          FsEntryLicenseReviewing(
              summary: summary(isFree: true, isCovered: true), busy: true));

      final field = find.text('License fee');
      expect(
          tester
              .widget<ExcludeFocus>(find
                  .ancestor(of: field, matching: find.byType(ExcludeFocus))
                  .first)
              .excluding,
          isTrue);
      expect(
          tester
              .widget<AbsorbPointer>(find
                  .ancestor(of: field, matching: find.byType(AbsorbPointer))
                  .first)
              .absorbing,
          isTrue);
    });

    testWidgets('a failure says so in the dialog, and Add license tries again',
        (tester) async {
      await pump(
          tester,
          FsEntryLicenseReviewing(
              summary: summary(isFree: true, isCovered: true), failed: true));

      expect(find.text("Couldn't add the license"), findsOneWidget);
      expect(find.byType(ArDriveNotice), findsOneWidget);
      await tester.tap(find.widgetWithText(ArDriveButtonNew, 'Add license'));
      verify(() => bloc.add(const FsEntryLicenseReviewConfirm())).called(1);
    });
  });
}
