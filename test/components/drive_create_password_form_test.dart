import 'package:ardrive/authentication/password/breached_password.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/drive_create_form.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart'
    show DrivePrivacy;
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

class _Breaches extends Fake implements BreachedPasswordCheck {
  final breached = <String>{};

  @override
  Future<bool?> isBreached(String password) async =>
      breached.contains(password);
}

/// The create drive dialog when the new private drive needs its own password:
/// the new-account rules, a confirmation, and a breach check before it goes.
void main() {
  late _MockDriveCreateCubit cubit;
  late _Breaches breaches;

  setUp(() {
    cubit = _MockDriveCreateCubit();
    breaches = _Breaches();
    whenListen(cubit, const Stream<DriveCreateState>.empty(),
        initialState: const DriveCreateInitial(privacy: DrivePrivacy.private));
    when(() => cubit.form).thenReturn(FormGroup({
      'privacy': FormControl<String>(value: DrivePrivacy.private.name),
    }));
    when(() => cubit.needsDrivePassword).thenReturn(true);
    when(() => cubit.submit(any(),
            drivePassword: any(named: 'drivePassword')))
        .thenAnswer((_) async {});
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ArDriveTheme(
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
          body: BlocProvider<DriveCreateCubit>.value(
            value: cubit,
            child: DriveCreateForm(breachCheck: breaches),
          ),
        ),
      ),
    ));
  }

  Finder field(String key) => find.descendant(
      of: find.byKey(Key(key)), matching: find.byType(EditableText));

  bool createEnabled(WidgetTester tester) => tester
      .widget<ArDriveButtonNew>(find.widgetWithText(ArDriveButtonNew, 'Create drive'))
      .isDisabled
      .let((disabled) => !disabled);

  testWidgets(
      'asks for a strong, confirmed drive password, refuses a breached one, '
      'and creates the drive with the password it was given', (tester) async {
    await pump(tester);

    expect(
        find.text(
            "Set a password for this drive. You'll need it to open the drive."),
        findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, 'Drive');
    await tester.enterText(field('newDrivePassword'), 'short');
    await tester.pump();
    expect(find.text('Use at least 12 characters.'), findsOneWidget);
    expect(createEnabled(tester), isFalse);

    const strong = 'Velvet harbour 47 lanterns drift';
    await tester.enterText(field('newDrivePassword'), strong);
    await tester.enterText(field('newDrivePasswordConfirm'), 'not the same');
    await tester.pump();
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(createEnabled(tester), isFalse);

    breaches.breached.add(strong);
    await tester.enterText(field('newDrivePasswordConfirm'), strong);
    await tester.pump();
    expect(createEnabled(tester), isTrue);
    await tester.tap(find.widgetWithText(ArDriveButtonNew, 'Create drive'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'This password has shown up in a data breach. Choose another.'),
        findsOneWidget);
    verifyNever(() => cubit.submit(any(),
        drivePassword: any(named: 'drivePassword')));

    const other = 'Copper meadow 92 kites unfold';
    await tester.enterText(field('newDrivePassword'), other);
    await tester.enterText(field('newDrivePasswordConfirm'), other);
    await tester.pump();
    await tester.tap(find.widgetWithText(ArDriveButtonNew, 'Create drive'));
    await tester.pumpAndSettle();
    verify(() => cubit.submit('Drive', drivePassword: other)).called(1);
  });

  testWidgets('with the sign-in password proven, no password is asked',
      (tester) async {
    when(() => cubit.needsDrivePassword).thenReturn(false);
    await pump(tester);

    expect(find.byKey(const Key('newDrivePassword')), findsNothing);
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
