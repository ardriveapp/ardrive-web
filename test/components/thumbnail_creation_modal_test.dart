import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/drive_explorer/thumbnail_creation/page/thumbnail_creation_modal.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

class _MockThumbnails extends Mock implements ThumbnailRepository {}

/// Making a thumbnail: the dialog explains it, makes it without leaving, and
/// says in itself when it could not.
void main() {
  late _MockThumbnails repository;

  setUp(() => repository = _MockThumbnails());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ThumbnailRepository>.value(value: repository)
        ],
        child: BlocProvider<DriveDetailCubit>.value(
          value: MockDriveDetailCubit(),
          child: ArDriveTheme(
            themeData: lightTheme(),
            child: MaterialApp(
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: ThumbnailCreationModal(
                  fileDataTableItem: createMockFileDataTableItem(name: 'a.png'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  ArDriveButtonNew button(WidgetTester tester, String text) =>
      tester.widget<ArDriveButtonNew>(find
          .byWidgetPredicate((w) => w is ArDriveButtonNew && w.text == text));

  testWidgets('is named for what it does, in words', (tester) async {
    await open(tester);

    expect(find.text('Create thumbnail'), findsNWidgets(2));
    expect(find.text('Confirm'), findsNothing);
    expect(find.textContaining('small image'), findsOneWidget);
    expect(button(tester, 'Cancel').variant, ButtonVariant.secondary);
  });

  testWidgets('while it works the primary is busy and Cancel is held',
      (tester) async {
    final done = Completer<void>();
    when(() => repository.uploadThumbnail(fileId: any(named: 'fileId')))
        .thenAnswer((_) => done.future);
    await open(tester);

    await tester.tap(find.widgetWithText(ArDriveButtonNew, 'Create thumbnail'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(ArDriveSpinner), findsOneWidget);
    expect(button(tester, 'Cancel').isDisabled, isTrue);
    expect(button(tester, 'Create thumbnail').isDisabled, isTrue);
    done.complete();
    await tester.pump();
  });

  testWidgets('a failure is a notice with Try again, and the dialog stays',
      (tester) async {
    when(() => repository.uploadThumbnail(fileId: any(named: 'fileId')))
        .thenThrow(Exception('network'));
    await open(tester);

    await tester.tap(find.widgetWithText(ArDriveButtonNew, 'Create thumbnail'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(ArDriveNotice), findsOneWidget);
    expect(find.text('Could not create the thumbnail'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    verify(() => repository.uploadThumbnail(fileId: any(named: 'fileId')))
        .called(2);
  });
}
