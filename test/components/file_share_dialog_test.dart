import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/file_share_dialog.dart';
import 'package:ardrive/components/share_warning.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class MockFileShareCubit extends MockCubit<FileShareState>
    implements FileShareCubit {}

/// The warnings in the share file dialog.
///
/// Both were small text in `strokeRed`, a border colour: short of AA on the
/// modal in both themes and close to unreadable in dark mode. They now use the
/// same panel as the drive dialog, where the colour is carried by the icon and
/// border and the sentence itself is readable.
void main() {
  late MockFileShareCubit cubit;

  setUp(() => cubit = MockFileShareCubit());

  Future<void> pumpState(WidgetTester tester, FileShareState state) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    whenListen(cubit, const Stream<FileShareState>.empty(),
        initialState: state);

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
          // The test font gives every character the full font size in width,
          // about twice a real font, so the key toggle's one-line label would
          // overflow the dialog here though it fits in the app.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(0.5)),
            child: child!,
          ),
          home: Scaffold(
            body: BlocProvider<FileShareCubit>.value(
              value: cubit,
              child: const FileShareDialog(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  FileShareLoadSuccess privateFile({
    bool isPending = false,
    bool keyIsInLink = false,
  }) =>
      FileShareLoadSuccess(
        fileName: 'notes.txt',
        fileShareLink: Uri.parse('https://app.ardrive.io/#/file/abc/view'),
        isPublicFile: false,
        isPending: isPending,
        fileKeyBase64: 'X123YZAB-CD4e5fgHIjKlmN6O7pqrStuVwxYzaBcd8E',
        keyIsInLink: keyIsInLink,
      );

  Finder warning(String text) => find.descendant(
        of: find.byType(ShareWarning),
        matching: find.textContaining(text),
      );

  testWidgets('says nothing in red for an ordinary private share',
      (tester) async {
    await pumpState(tester, privateFile());

    expect(find.byType(ShareWarning), findsNothing);
  });

  testWidgets('warns that a link holding the key is the file', (tester) async {
    await pumpState(tester, privateFile(keyIsInLink: true));

    expect(warning('This link now opens the file on its own.'), findsOneWidget);
  });

  testWidgets('warns that a pending file may not open yet', (tester) async {
    await pumpState(tester, privateFile(isPending: true));

    expect(warning('This file is still pending'), findsOneWidget);
  });
}
