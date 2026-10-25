import 'package:ardrive/blocs/blocs.dart';
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

  testWidgets('a refused payment offers credits instead', (tester) async {
    await pump(tester, const FsEntryLicenseFailure(isPaymentError: true));

    expect(actions(tester).last, ('Buy credits', ButtonVariant.primary));
  });
}
