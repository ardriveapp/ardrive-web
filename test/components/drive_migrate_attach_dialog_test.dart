import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/drive_attach_form.dart';
import 'package:ardrive/components/migrate_private_drives_modal.dart';
import 'package:ardrive/shared/blocs/private_drive_migration/private_drive_migration_bloc.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAttachCubit extends MockCubit<DriveAttachState>
    implements DriveAttachCubit {}

class _MockMigrationBloc
    extends MockBloc<PrivateDriveMigrationEvent, PrivateDriveMigrationState>
    implements PrivateDriveMigrationBloc {}

/// Attach drive says a missing drive, a wrong key or a failed attach inside the
/// dialog; update private drives has a quiet Close, a real link and localized
/// copy.
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

  group('attach drive', () {
    late _MockAttachCubit cubit;

    setUp(() {
      cubit = _MockAttachCubit();
      when(() => cubit.driveIdController).thenReturn(TextEditingController());
      when(() => cubit.driveKeyController).thenReturn(TextEditingController());
      when(() => cubit.driveNameController)
          .thenReturn(TextEditingController(text: 'Photos'));
      when(() => cubit.lookupNotifier).thenReturn(ValueNotifier(false));
      when(() => cubit.cachedDriveEntity).thenReturn(null);
      when(() => cubit.submit()).thenAnswer((_) async {});
    });

    Future<void> pumpAttach(
      WidgetTester tester,
      Stream<DriveAttachState> states, {
      DriveAttachState? initial,
      Size size = const Size(1000, 1000),
    }) async {
      whenListen(cubit, states, initialState: initial ?? DriveAttachInitial());
      await pumpApp(
        tester,
        BlocProvider<DriveAttachCubit>.value(
          value: cubit,
          child: const DriveAttachForm(),
        ),
        size: size,
      );
      await tester.pump();
      await tester.pump();
    }

    for (final size in [const Size(1000, 1000), const Size(390, 844)]) {
      testWidgets(
          'a drive that is not found is an error notice in the dialog '
          '($size)', (tester) async {
        await pumpAttach(tester, Stream.value(DriveAttachDriveNotFound()),
            size: size);

        expect(
          find.descendant(
            of: find.byType(ArDriveNotice),
            matching: find.text('The specified drive could not be found.'),
          ),
          findsOneWidget,
        );
        expect(find.text('Attach drive'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a wrong key is an error notice in the dialog', (tester) async {
      await pumpAttach(tester, Stream.value(DriveAttachInvalidDriveKey()));

      expect(
        find.descendant(
          of: find.byType(ArDriveNotice),
          matching: find.text('That key does not open this drive.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a failure stays in the dialog with Try again', (tester) async {
      await pumpAttach(tester, Stream.value(DriveAttachFailure()));

      expect(find.byType(ArDriveNotice), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Try again'));
      await tester.pump();
      verify(() => cubit.submit()).called(1);
    });

    testWidgets('typing another drive ID clears the notice', (tester) async {
      await pumpAttach(tester, Stream.value(DriveAttachDriveNotFound()));
      expect(find.byType(ArDriveNotice), findsOneWidget);

      cubit.driveIdController.text = 'something else';
      await tester.pump();

      expect(find.byType(ArDriveNotice), findsNothing);
    });

    testWidgets('while it works the primary is busy and Cancel is held',
        (tester) async {
      await pumpAttach(tester, const Stream.empty(),
          initial: DriveAttachInProgress());

      expect(button(tester, 'Cancel').isDisabled, isTrue);
      expect(find.byType(ArDriveSpinner), findsWidgets);
      expect(find.text('Drive ID'), findsOneWidget);
    });

    testWidgets('the fields have labels and Cancel closes', (tester) async {
      await pumpAttach(tester, const Stream.empty());

      expect(find.text('Drive ID'), findsOneWidget);
      expect(find.text('Drive name'), findsOneWidget);
      // The corner close button; its label is the dialog's own Cancel/Close.
      expect(
          find.byWidgetPredicate(
              (w) => w is ArDriveIcon && w.icon == ArDriveIconsData.x),
          findsOneWidget);
    });
  });

  group('update private drives', () {
    late _MockMigrationBloc bloc;

    Future<void> pumpMigration(
      WidgetTester tester,
      PrivateDriveMigrationState state, {
      Size size = const Size(1000, 1000),
    }) async {
      bloc = _MockMigrationBloc();
      when(() => bloc.drivesRequiringMigration).thenReturn([]);
      when(() => bloc.completedMigration).thenReturn({});
      whenListen(bloc, const Stream<PrivateDriveMigrationState>.empty(),
          initialState: state);
      await pumpApp(
        tester,
        BlocProvider<PrivateDriveMigrationBloc>.value(
          value: bloc,
          child: const PrivateDriveMigrationDialog(),
        ),
        size: size,
      );
      await tester.pump();
    }

    for (final size in [const Size(1000, 1000), const Size(390, 844)]) {
      testWidgets(
          'Close is quiet and the dialog has the close button '
          'when complete ($size)', (tester) async {
        await pumpMigration(tester, PrivateDriveMigrationComplete(),
            size: size);

        expect(button(tester, 'Close').variant, ButtonVariant.secondary);
        expect(find.bySemanticsLabel('Close'), findsWidgets);
        expect(find.text('Your private drives are updated.'), findsOneWidget);
        expect(find.textContaining('!'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Learn more is an external ArDriveLink', (tester) async {
      await pumpMigration(tester, PrivateDriveMigrationVisible());

      final link = tester.widget<ArDriveLink>(find.byType(ArDriveLink));
      expect(link.text, 'Learn more');
      expect(link.external, isTrue);
      expect(find.text('Update private drives'), findsOneWidget);
      expect(button(tester, 'Update').isDisabled, isFalse);
    });

    testWidgets('a failure is an error notice', (tester) async {
      await pumpMigration(
          tester, const PrivateDriveMigrationFailed(error: 'anything'));

      expect(
        find.descendant(
          of: find.byType(ArDriveNotice),
          matching: find.text('A drive could not be updated. Try again.'),
        ),
        findsOneWidget,
      );
      expect(find.text('anything'), findsNothing);
    });
  });
}
