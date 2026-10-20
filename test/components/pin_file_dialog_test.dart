import 'dart:async';
import 'dart:io';

import 'package:ardrive/blocs/pin_file/pin_file_bloc.dart';
import 'package:ardrive/components/pin_file_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPinFileBloc extends MockBloc<PinFileEvent, PinFileState>
    implements PinFileBloc {}

/// The New File Pin dialog's ID field.
///
/// It said "The ID provided is not valid" from the first character typed,
/// since every ID is an invalid one until it is finished. And while the ID
/// was looked up, the field greyed out with nothing to say why.
void main() {
  const notValid = 'The ID provided is not valid';

  /// The real face, so the dialog lays out at its real width. In the test
  /// font every glyph is a square em and the field's label overflows. Loaded
  /// here: a real file read never finishes inside `testWidgets`.
  setUpAll(() async {
    final loader = FontLoader('packages/ardrive_ui/Wavehaus');
    for (final file in Directory('packages/ardrive_ui/assets/fonts')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('Wavehaus'))) {
      final bytes = await file.readAsBytes();
      loader.addFont(
        Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
      );
    }
    await loader.load();
  });
  const fullTransactionId = 'aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789-_aBcDe';

  group('showsInvalidIdError', () {
    test('not while the text could still become an ID', () {
      expect(showsInvalidIdError('a', settled: false), isFalse);
      expect(showsInvalidIdError('aBcDe-_+0', settled: false), isFalse);
      // A transaction ID passes a file ID's length on its way to its own.
      expect(
        showsInvalidIdError(fullTransactionId.substring(0, 40),
            settled: false),
        isFalse,
      );
    });

    test('once it is as long as the longest ID', () {
      expect(showsInvalidIdError('${fullTransactionId}x', settled: false),
          isTrue);
    });

    test('once it holds a character no ID has', () {
      expect(showsInvalidIdError('abc!', settled: false), isTrue);
      expect(showsInvalidIdError('abc def', settled: false), isTrue);
    });

    test('once the reader is done with it', () {
      expect(showsInvalidIdError('abc', settled: true), isTrue);
    });
  });

  group('the ID field', () {
    late _MockPinFileBloc bloc;
    late StreamController<PinFileState> states;

    PinFileState invalid(String id) => PinFileFieldsValidationError(
          id: id,
          name: '',
          idValidation: IdValidationResult.invalid,
          nameValidation: NameValidationResult.required,
          cancelled: false,
          networkError: false,
          isArFsEntityValid: true,
          isArFsEntityPublic: true,
          doesDataTransactionExist: true,
        );

    setUp(() {
      bloc = _MockPinFileBloc();
      states = StreamController<PinFileState>.broadcast();
      whenListen(bloc, states.stream, initialState: const PinFileInitial());
      when(() => bloc.nameTextController).thenReturn(TextEditingController());
    });

    tearDown(() => states.close());

    Future<void> pumpDialog(WidgetTester tester) async {
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
            home: Scaffold(
              body: BlocProvider<PinFileBloc>.value(
                value: bloc,
                child: const PinFileDialog(),
              ),
            ),
          ),
        ),
      );
    }

    Finder idField() => find.byType(TextField).first;

    /// Types [text] one character at a time, the bloc answering each one as
    /// it does: the text is not a valid ID yet.
    Future<void> type(WidgetTester tester, String text) async {
      for (var i = 1; i <= text.length; i++) {
        final sofar = text.substring(0, i);
        await tester.enterText(idField(), sofar);
        states.add(invalid(sofar));
        await tester.pump();
      }
    }

    testWidgets('says nothing about an ID still being typed', (tester) async {
      await pumpDialog(tester);
      await tester.tap(idField());

      await type(tester, fullTransactionId.substring(0, 42));

      expect(find.text(notValid), findsNothing);
    });

    testWidgets('says so once the reader leaves the field', (tester) async {
      await pumpDialog(tester);
      await tester.tap(idField());
      await type(tester, 'abc');
      expect(find.text(notValid), findsNothing);

      // Into the name field.
      await tester.tap(find.byType(TextField).last);
      await tester.pump();

      expect(find.text(notValid), findsOneWidget);
    });

    testWidgets('says so at once for a pasted ID', (tester) async {
      await pumpDialog(tester);
      await tester.tap(idField());

      await tester.enterText(idField(), 'not-a-whole-id');
      states.add(invalid('not-a-whole-id'));
      await tester.pump();

      expect(find.text(notValid), findsOneWidget);
    });

    testWidgets('shows that a lookup is running', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpDialog(tester);

      states.add(const PinFileNetworkCheckRunning(
        id: fullTransactionId,
        name: '',
        idValidation: IdValidationResult.validTransactionId,
        nameValidation: NameValidationResult.required,
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Said in words, where a screen reader can reach it: the disabled
      // field hides everything inside it.
      expect(find.bySemanticsLabel('Looking up this ID...'), findsOneWidget);
      expect(find.text(notValid), findsNothing);

      semantics.dispose();
    });

    testWidgets('and stops showing it once the lookup is done',
        (tester) async {
      await pumpDialog(tester);

      states.add(const PinFileNetworkCheckRunning(
        id: fullTransactionId,
        name: '',
        idValidation: IdValidationResult.validTransactionId,
        nameValidation: NameValidationResult.required,
      ));
      await tester.pump();
      states.add(invalid('x!'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Looking up this ID...'), findsNothing);
    });
  });
}
