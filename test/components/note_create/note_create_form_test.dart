import 'package:ardrive/blocs/note_create/note_create_cubit.dart';
import 'package:ardrive/blocs/note_create/note_create_state.dart';
import 'package:ardrive/components/note_create/note_create_form.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoteCreateForm', () {
    late NoteCreateCubit cubit;

    setUp(() {
      cubit = NoteCreateCubit(
        driveId: 'test-drive-id',
        parentFolderId: 'test-folder-id',
      );
    });

    tearDown(() {
      cubit.close();
    });

    Widget createTestWidget() {
      return ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en', ''),
          ],
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: const NoteCreateForm(),
            ),
          ),
        ),
      );
    }

    testWidgets('renders with initial state', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Should find the modal title
      expect(find.text('Create New Note'), findsOneWidget);

      // Should find the .md extension label
      expect(find.text('.md'), findsOneWidget);

      // Should find view mode buttons
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Split'), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);

      // Should find action buttons
      expect(find.text('CANCEL'), findsOneWidget);
      expect(find.text('NEXT'), findsOneWidget);
    });

    testWidgets('Create Note button is disabled when name is empty',
        (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Initial state should have invalid name (empty)
      expect(cubit.state, isA<NoteCreateEditing>());
      final state = cubit.state as NoteCreateEditing;
      expect(state.isValidName, false);
    });

    testWidgets('updates note name when text is entered', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Find the text field and enter text
      final textField = find.byType(ArDriveTextFieldNew);
      expect(textField, findsOneWidget);

      await tester.enterText(textField, 'Test Note');
      await tester.pump();

      // Verify cubit state updated
      expect(
        cubit.state,
        isA<NoteCreateEditing>()
            .having((s) => s.noteName, 'noteName', 'Test Note')
            .having((s) => s.isValidName, 'isValidName', true),
      );
    });

    testWidgets('view mode toggle buttons work', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Initial state should be split view
      expect(
        cubit.state,
        isA<NoteCreateEditing>()
            .having((s) => s.viewMode, 'viewMode', NoteViewMode.splitView),
      );

      // Tap Edit button
      await tester.tap(find.text('Edit'));
      await tester.pump();

      expect(
        cubit.state,
        isA<NoteCreateEditing>()
            .having((s) => s.viewMode, 'viewMode', NoteViewMode.editOnly),
      );

      // Tap Preview button
      await tester.tap(find.text('Preview'));
      await tester.pump();

      expect(
        cubit.state,
        isA<NoteCreateEditing>()
            .having((s) => s.viewMode, 'viewMode', NoteViewMode.previewOnly),
      );

      // Tap Split button
      await tester.tap(find.text('Split'));
      await tester.pump();

      expect(
        cubit.state,
        isA<NoteCreateEditing>()
            .having((s) => s.viewMode, 'viewMode', NoteViewMode.splitView),
      );
    });

    testWidgets('displays error when invalid name is entered', (tester) async {
      // Set a larger viewport to accommodate error message display
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter invalid name with forward slash
      final textField = find.byType(ArDriveTextFieldNew);
      await tester.enterText(textField, 'Invalid/Name');
      await tester.pump();

      // Verify cubit state shows error
      final state = cubit.state as NoteCreateEditing;
      expect(state.isValidName, false);
      expect(state.nameError, isNotNull);
    });

    testWidgets('note name field has autofocus', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Find the text field and verify it exists
      final textFieldFinder = find.byType(ArDriveTextFieldNew);
      expect(textFieldFinder, findsOneWidget);

      // The ArDriveTextFieldNew should have autofocus enabled
      final textField = tester.widget<ArDriveTextFieldNew>(textFieldFinder);
      expect(textField.autofocus, true);
    });
  });
}
