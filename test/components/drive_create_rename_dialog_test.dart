import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/drive_rename/drive_rename_cubit.dart';
import 'package:ardrive/components/drive_create_form.dart';
import 'package:ardrive/components/drive_rename_form.dart';
import 'package:ardrive/components/progress_dialog.dart';
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

class _MockDriveRenameCubit extends MockCubit<DriveRenameState>
    implements DriveRenameCubit {}

class _MockDriveDetailCubit extends MockCubit<DriveDetailState>
    implements DriveDetailCubit {}

/// Create and rename drive keep their work in the dialog: the primary is busy,
/// Cancel is held, and a failure or a name clash is said in the dialog, which
/// stays open. Neither opens a second dialog.
void main() {
  Future<void> pumpApp(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1000, 1000),
  }) async {
    await tester.binding.setSurfaceSize(size);
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
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ));
  }

  ArDriveButtonNew button(WidgetTester tester, String text) => tester
      .widget<ArDriveButtonNew>(find.widgetWithText(ArDriveButtonNew, text));

  group('create drive', () {
    late _MockDriveCreateCubit cubit;
    const initial = DriveCreateInitial(privacy: DrivePrivacy.public);

    setUp(() {
      cubit = _MockDriveCreateCubit();
      when(() => cubit.form).thenReturn(FormGroup({
        'privacy': FormControl<String>(value: DrivePrivacy.public.name),
      }));
      when(() => cubit.needsDrivePassword).thenReturn(false);
      when(() => cubit.drivePasswordAsk).thenReturn(null);
      when(() => cubit.submit(any())).thenAnswer((_) async {});
    });

    Future<void> pumpCreate(
      WidgetTester tester,
      Stream<DriveCreateState> states, {
      Size size = const Size(1000, 1000),
    }) async {
      whenListen(cubit, states, initialState: initial);
      await pumpApp(
        tester,
        BlocProvider<DriveCreateCubit>.value(
          value: cubit,
          child: const DriveCreateForm(),
        ),
        size: size,
      );
      await tester.enterText(find.byType(EditableText).first, 'Photos');
      await tester.pump();
    }

    testWidgets(
        'while it works the primary is busy, Cancel is held and no '
        'progress dialog opens', (tester) async {
      await pumpCreate(
        tester,
        Stream.value(const DriveCreateInProgress(privacy: DrivePrivacy.public)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(ProgressDialog), findsNothing);
      expect(find.byType(ArDriveSpinner), findsWidgets);
      expect(button(tester, 'Cancel').isDisabled, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    for (final size in [const Size(1000, 1000), const Size(390, 844)]) {
      testWidgets(
          'a failure is an error notice in the dialog, with Try again '
          '($size)', (tester) async {
        await pumpCreate(
          tester,
          Stream.value(const DriveCreateFailure(privacy: DrivePrivacy.public)),
          size: size,
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.descendant(
            of: find.byType(ArDriveNotice),
            matching: find.textContaining('Something went wrong'),
          ),
          findsOneWidget,
        );
        expect(find.text('Create drive'), findsWidgets);
        expect(tester.takeException(), isNull);

        await tester.pumpAndSettle();

        await tester.tap(find.text('Try again'));
        await tester.pump();
        verify(() => cubit.submit('Photos')).called(1);
      });
    }

    testWidgets('a wallet that cannot make drive keys says so in the dialog',
        (tester) async {
      await pumpCreate(
        tester,
        Stream.value(const DriveCreateFailure(
          privacy: DrivePrivacy.public,
          walletCantMakeDriveKeys: true,
        )),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(ArDriveNotice), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    // submit returns without emitting when Wander can't be reached and the
    // person cancels: the failure said before must not come back.
    testWidgets(
        'Try again that ends without a new failure leaves no old notice',
        (tester) async {
      final states = StreamController<DriveCreateState>();
      addTearDown(states.close);
      await pumpCreate(tester, states.stream);
      states.add(const DriveCreateFailure(privacy: DrivePrivacy.public));
      await tester.pumpAndSettle();
      expect(find.byType(ArDriveNotice), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.byType(ArDriveNotice), findsNothing);
    });

    testWidgets('while it works the inputs take no keyboard input',
        (tester) async {
      await pumpCreate(
        tester,
        Stream.value(const DriveCreateInProgress(privacy: DrivePrivacy.public)),
      );
      await tester.pump();
      await tester.pump();

      final field =
          tester.widget<EditableText>(find.byType(EditableText).first);
      expect(field.readOnly, isTrue);
    });

    testWidgets('the name field has its label and Cancel closes',
        (tester) async {
      await pumpCreate(tester, const Stream.empty());

      expect(find.text('Drive name'), findsOneWidget);
      expect(find.bySemanticsLabel('Close'), findsOneWidget);
    });
  });

  group('rename drive', () {
    late _MockDriveRenameCubit cubit;
    late _MockDriveDetailCubit detail;

    setUp(() {
      cubit = _MockDriveRenameCubit();
      detail = _MockDriveDetailCubit();
      when(() => detail.refreshDriveDataTable()).thenAnswer((_) async {});
      when(() => cubit.submit(
            newName: any(named: 'newName'),
            proceedIfHasConflicts: any(named: 'proceedIfHasConflicts'),
          )).thenAnswer((_) async {});
    });

    Future<void> pumpRename(
      WidgetTester tester,
      Stream<DriveRenameState> states,
    ) async {
      whenListen(cubit, states, initialState: DriveRenameInitial());
      await pumpApp(
        tester,
        MultiBlocProvider(
          providers: [
            BlocProvider<DriveRenameCubit>.value(value: cubit),
            BlocProvider<DriveDetailCubit>.value(value: detail),
          ],
          child: const DriveRenameForm(driveName: 'Photos'),
        ),
      );
      await tester.enterText(find.byType(EditableText).first, 'Archive');
      await tester.pump();
    }

    testWidgets(
        'a name clash is said in the dialog and the primary becomes '
        'Rename anyway', (tester) async {
      await pumpRename(
        tester,
        Stream.value(const DriveNameAlreadyExists('Archive')),
      );
      await tester.pump();
      await tester.pump();

      expect(
          find.text('A drive with this name already exists.'), findsOneWidget);
      expect(find.text('Warning'), findsNothing);
      expect(find.text('Proceed'), findsNothing);

      await tester.pumpAndSettle();

      await tester.tap(find.text('Rename anyway'));
      await tester.pump();
      verify(() => cubit.submit(
            newName: 'Archive',
            proceedIfHasConflicts: true,
          )).called(1);
    });

    testWidgets('typing another name clears the clash', (tester) async {
      await pumpRename(
        tester,
        Stream.value(const DriveNameAlreadyExists('Archive')),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Rename anyway'), findsOneWidget);

      await tester.enterText(find.byType(EditableText).first, 'Other');
      await tester.pump();

      expect(find.text('Rename anyway'), findsNothing);
      expect(find.text('Rename'), findsWidgets);
    });

    testWidgets('while it works the primary is busy and Cancel is held',
        (tester) async {
      await pumpRename(tester, Stream.value(DriveRenameInProgress()));
      await tester.pump();
      await tester.pump();

      expect(button(tester, 'Cancel').isDisabled, isTrue);
      expect(find.byType(ArDriveSpinner), findsWidgets);
      expect(find.byType(ProgressDialog), findsNothing);
    });

    testWidgets('a failure is an error notice with Try again, in the dialog',
        (tester) async {
      await pumpRename(
        tester,
        Stream.value(const DriveRenameFailure()),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(ArDriveNotice),
          matching: find.textContaining('Something went wrong'),
        ),
        findsOneWidget,
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Try again'));
      await tester.pump();
      verify(() => cubit.submit(
            newName: 'Archive',
            proceedIfHasConflicts: false,
          )).called(1);
    });

    testWidgets('two quick presses of Rename ask the cubit once',
        (tester) async {
      final answer = Completer<void>();
      when(() => cubit.submit(
            newName: any(named: 'newName'),
            proceedIfHasConflicts: any(named: 'proceedIfHasConflicts'),
          )).thenAnswer((_) => answer.future);
      await pumpRename(tester, const Stream.empty());

      // Both land before a frame is drawn, as two fast clicks can.
      await tester.tap(find.widgetWithText(ArDriveButtonNew, 'Rename'));
      await tester.tap(find.widgetWithText(ArDriveButtonNew, 'Rename'));
      await tester.pump();

      verify(() => cubit.submit(
            newName: 'Archive',
            proceedIfHasConflicts: false,
          )).called(1);
      answer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Try again is not offered for a name that cannot be saved',
        (tester) async {
      await pumpRename(
        tester,
        Stream.value(const DriveRenameFailure()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);

      await tester.enterText(find.byType(EditableText).first, '');
      await tester.pumpAndSettle();

      expect(find.text('Try again'), findsNothing);
      verifyNever(() => cubit.submit(
            newName: any(named: 'newName'),
            proceedIfHasConflicts: any(named: 'proceedIfHasConflicts'),
          ));
    });

    testWidgets('the name field is labelled', (tester) async {
      await pumpRename(tester, const Stream.empty());
      expect(find.text('Drive name'), findsOneWidget);
    });
  });
}
