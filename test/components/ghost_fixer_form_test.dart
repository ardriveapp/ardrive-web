import 'package:ardrive/blocs/ghost_fixer/ghost_fixer_cubit.dart';
import 'package:ardrive/components/ghost_fixer_form.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

class _MockGhostFixerCubit extends MockCubit<GhostFixerState>
    implements GhostFixerCubit {}

/// Fix folder: a folder's metadata was never found, and the owner gives it a
/// name and a place to recreate it.
void main() {
  late _MockGhostFixerCubit cubit;

  FolderEntry folder(String id, {String? parent}) => FolderEntry(
        id: id,
        driveId: 'drive',
        name: id,
        parentFolderId: parent,
        path: '',
        dateCreated: DateTime(2024),
        lastUpdated: DateTime(2024),
        isGhost: false,
        isHidden: false,
      );

  setUp(() {
    cubit = _MockGhostFixerCubit();
    when(() => cubit.state).thenReturn(GhostFixerFolderLoadSuccess(
      viewingRootFolder: true,
      viewingFolder: FolderWithContents(
        folder: folder('root'),
        subfolders: [folder('Photos', parent: 'root')],
        files: const [],
      ),
      movingEntryId: 'ghost',
    ));
    when(() => cubit.submit(any())).thenAnswer((_) async {});
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
            body: BlocProvider<GhostFixerCubit>.value(
              value: cubit,
              child: GhostFixerForm(driveDetailCubit: MockDriveDetailCubit()),
            ),
          ),
        ),
      ),
    );
  }

  ArDriveButtonNew button(WidgetTester tester, String text) => tester
      .widget<ArDriveButtonNew>(find.widgetWithText(ArDriveButtonNew, text));

  testWidgets('is a standard dialog with Cancel and Fix', (tester) async {
    await pump(tester);

    expect(find.byType(ArDriveStandardModalNew), findsOneWidget);
    expect(find.byType(ArDriveTextFieldNew), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(button(tester, 'Cancel').variant, ButtonVariant.secondary);
    expect(button(tester, 'FIX').variant, ButtonVariant.primary);
  });

  testWidgets('Fix waits for a valid name, then submits it', (tester) async {
    await pump(tester);
    expect(button(tester, 'FIX').isDisabled, isTrue);

    await tester.enterText(find.byType(TextField), 'Recovered');
    await tester.pump();

    expect(button(tester, 'FIX').isDisabled, isFalse);
    await tester.tap(find.text('FIX'));
    verify(() => cubit.submit('Recovered')).called(1);
  });
}
