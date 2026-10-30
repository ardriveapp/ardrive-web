import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/drive_create_form.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart'
    show DrivePrivacy;
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:reactive_forms/reactive_forms.dart';

class _MockDriveCreateCubit extends MockCubit<DriveCreateState>
    implements DriveCreateCubit {}

/// The create drive dialog when the sign-in password is unproven: one field
/// for the existing drive password, no confirmation and no new-password
/// rules, because it is checked by opening one of the user's drives.
void main() {
  late _MockDriveCreateCubit cubit;

  const initial = DriveCreateInitial(privacy: DrivePrivacy.private);

  setUp(() {
    cubit = _MockDriveCreateCubit();
    when(() => cubit.form).thenReturn(FormGroup({
      'privacy': FormControl<String>(value: DrivePrivacy.private.name),
    }));
    when(() => cubit.needsDrivePassword).thenReturn(true);
    when(() => cubit.submit(any(), drivePassword: any(named: 'drivePassword')))
        .thenAnswer((_) async {});
  });

  Future<void> pump(
    WidgetTester tester, {
    Stream<DriveCreateState> states = const Stream.empty(),
    Size size = const Size(1000, 1000),
    bool dark = false,
  }) async {
    whenListen(cubit, states, initialState: initial);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ArDriveTheme(
      themeData: dark ? null : lightTheme(),
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
            child: BlocProvider<DriveCreateCubit>.value(
              value: cubit,
              child: const DriveCreateForm(),
            ),
          ),
        ),
      ),
    ));
  }

  Finder field(String key) => find.descendant(
      of: find.byKey(Key(key)), matching: find.byType(EditableText));

  bool createEnabled(WidgetTester tester) => !tester
      .widget<ArDriveButtonNew>(
          find.widgetWithText(ArDriveButtonNew, 'Create drive'))
      .isDisabled;

  for (final (name, size, dark) in [
    ('desktop, light', const Size(1000, 1000), false),
    ('390 px, dark', const Size(390, 844), true),
  ]) {
    testWidgets(
        '$name: one drive password field, no confirmation, and the drive is '
        'created with the password typed', (tester) async {
      await pump(tester, size: size, dark: dark);

      expect(find.text('Enter your drive password'), findsOneWidget);
      expect(find.byType(EditableText), findsNWidgets(2));
      expect(find.textContaining('characters'), findsNothing);

      await tester.enterText(find.byType(EditableText).first, 'Drive');
      await tester.pump();
      expect(createEnabled(tester), isFalse);

      await tester.enterText(field('drivePassword'), 'short');
      await tester.pump();
      expect(createEnabled(tester), isTrue);

      await tester.tap(find.widgetWithText(ArDriveButtonNew, 'Create drive'));
      await tester.pumpAndSettle();
      verify(() => cubit.submit('Drive', drivePassword: 'short')).called(1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'a password that opens none of their drives says so under the field',
      (tester) async {
    await pump(tester,
        states: Stream.value(const DriveCreateDrivePasswordRejected(
            privacy: DrivePrivacy.private,
            reason: DriveUnlockFailure.wrongPassword)));
    await tester.pumpAndSettle();

    expect(
        find.text("That password didn't open your private drives. Try again."),
        findsOneWidget);

    await tester.enterText(field('drivePassword'), 'another try');
    await tester.pump();
    expect(
        find.text("That password didn't open your private drives. Try again."),
        findsNothing,
        reason: 'typing again clears what the last check said');
  });

  testWidgets('a check that could not reach the network says that instead',
      (tester) async {
    await pump(tester,
        states: Stream.value(const DriveCreateDrivePasswordRejected(
            privacy: DrivePrivacy.private,
            reason: DriveUnlockFailure.unavailable)));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't reach the network. Try again."), findsOneWidget);
    expect(
        find.text("That password didn't open your private drives. Try again."),
        findsNothing);
  });

  testWidgets('with the sign-in password proven, no password is asked',
      (tester) async {
    when(() => cubit.needsDrivePassword).thenReturn(false);
    await pump(tester);

    expect(find.byKey(const Key('drivePassword')), findsNothing);
  });

  testWidgets('the drive password field asks the browser for the saved one',
      (tester) async {
    await pump(tester);

    final textField = tester.widget<TextField>(find.descendant(
        of: find.byKey(const Key('drivePassword')),
        matching: find.byType(TextField)));
    expect(textField.autofillHints, [AutofillHints.password]);
  });
}
