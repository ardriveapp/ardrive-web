import 'package:ardrive/blocs/bulk_import/bulk_import_bloc.dart';
import 'package:ardrive/blocs/bulk_import/bulk_import_event.dart';
import 'package:ardrive/blocs/bulk_import/bulk_import_state.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/arfs/use_cases/bulk_import_files.dart';
import 'package:ardrive/core/arfs/use_cases/check_folder_conflicts.dart';
import 'package:ardrive/pages/drive_detail/components/bulk_import_modal.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockBulkImportBloc extends MockBloc<BulkImportEvent, BulkImportState>
    implements BulkImportBloc {}

class _FakeEvent extends Fake implements BulkImportEvent {}

/// Importing files from a deployment: conflicts, failure and a cancelled
/// import are states of the one dialog, not dialogs on top of it.
void main() {
  late _MockBulkImportBloc bloc;

  setUpAll(() => registerFallbackValue(_FakeEvent()));
  setUp(() => bloc = _MockBulkImportBloc());

  /// Opens the modal the way the New menu does, so a second dialog on top
  /// would be a second route.
  Future<void> open(
    WidgetTester tester,
    BulkImportState state, {
    Size size = const Size(1200, 900),
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    whenListen(
      bloc,
      const Stream<BulkImportState>.empty(),
      initialState: state,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ActivityTracker(),
        child: ArDriveTheme(
          themeData: lightTheme(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAnimatedDialog(
                  context,
                  barrierDismissible: false,
                  content: BlocProvider<BulkImportBloc>.value(
                    value: bloc,
                    child: const BulkImportModal(
                      driveId: 'drive-id',
                      parentFolderId: 'folder-id',
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  List<String> buttons(WidgetTester tester) => tester
      .widgetList<ArDriveButtonNew>(find.byType(ArDriveButtonNew))
      .map((b) => b.text)
      .toList();

  testWidgets('conflicts are this dialog, and Replace answers the bloc',
      (tester) async {
    await open(
      tester,
      const BulkImportFileConflicts(
        manifestTxId: 'tx-id',
        conflicts: [
          FileTreeConflict(
            filePath: 'a/b.txt',
            fileName: 'b.txt',
            parentFolderId: 'p',
            existingFileId: 'old',
            newFileId: 'new',
          ),
        ],
      ),
    );

    expect(find.text('Files already exist'), findsOneWidget);
    expect(find.text('a/b.txt'), findsOneWidget);
    expect(find.byType(ArDriveStandardModalNew), findsOneWidget,
        reason: 'one dialog, never one on another');
    expect(buttons(tester), ['Cancel', 'Replace files']);

    await tester.tap(find.widgetWithText(ArDriveButtonNew, 'Replace files'));
    await tester.pump();

    final event = verify(() => bloc.add(captureAny())).captured.single;
    expect(event, isA<ReplaceConflictingFiles>());
    expect((event as ReplaceConflictingFiles).manifestTxId, 'tx-id');
  });

  testWidgets('Cancel on the conflicts closes the one dialog, once',
      (tester) async {
    await open(
      tester,
      const BulkImportFileConflicts(manifestTxId: 'tx-id', conflicts: []),
    );

    await tester.tap(find.widgetWithText(ArDriveButtonNew, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(ArDriveStandardModalNew), findsNothing);
    // The page under it is still there: it was not popped a second time.
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a failure is a notice in the dialog, which can be retried',
      (tester) async {
    await open(
      tester,
      const BulkImportError(
        'The deployment was not found.',
        null,
        false,
        BulkImportErrorReason.notFound,
      ),
    );

    expect(find.byType(ArDriveStandardModalNew), findsOneWidget);
    expect(find.byType(ArDriveNotice), findsOneWidget);
    expect(find.text("That deployment couldn't be found."), findsOneWidget,
        reason: 'worded by the dialog, not the bloc');
    expect(find.text('The deployment was not found.'), findsNothing);
    expect(find.text('Import from deployment'), findsOneWidget);
    expect(buttons(tester), ['Cancel', 'Import']);
    expect(find.text('OK'), findsNothing);
  });

  testWidgets('a Turbo payment failure offers credits in the notice',
      (tester) async {
    await open(
      tester,
      const BulkImportError('Add credits to continue.', null, true),
    );
    expect(find.textContaining('free upload allowance has been used up'),
        findsOneWidget);

    expect(find.byType(ArDriveStandardModalNew), findsOneWidget);
    expect(find.text('Buy credits'), findsOneWidget);
  });

  testWidgets('a cancelled import says how many files came in, with a Close',
      (tester) async {
    await open(tester, const BulkImportCancelled(numberOfFilesImported: 3));

    expect(find.text('Import cancelled'), findsOneWidget);
    expect(
        find.text('3 files were imported before it stopped.'), findsOneWidget);
    expect(buttons(tester), ['Close']);
  });

  testWidgets('while it loads the primary is busy and Cancel is held',
      (tester) async {
    await open(tester, const BulkImportLoadingManifest('tx-id'), settle: false);

    expect(find.text('Loading deployment'), findsOneWidget);
    final cancel = tester.widget<ArDriveButtonNew>(
      find.widgetWithText(ArDriveButtonNew, 'Cancel'),
    );
    expect(cancel.isDisabled, isTrue);
    final importButton =
        tester.widgetList<ArDriveButtonNew>(find.byType(ArDriveButtonNew)).last;
    expect(importButton.isDisabled, isTrue);
    expect(
      find.descendant(
        of: find.byType(ArDriveModalActions),
        matching: find.byType(ArDriveSpinner),
      ),
      findsOneWidget,
      reason: 'the primary is busy',
    );
  });

  testWidgets('nothing in it says manifest', (tester) async {
    await open(tester, const BulkImportInitial());

    expect(find.textContaining(RegExp('manifest', caseSensitive: false)),
        findsNothing);
    expect(find.text('Deployment ID'), findsOneWidget);
  });

  testWidgets('the review scrolls inside the dialog on a short window',
      (tester) async {
    await open(
      tester,
      BulkImportReviewingManifest(
        manifestTxId: 'tx-id',
        files: [
          for (var i = 0; i < 40; i++)
            ManifestFileEntry(
              id: 'id$i',
              path: 'dir/file$i.txt',
              name: 'file$i.txt',
              dataTxId: 'tx$i',
              contentType: 'text/plain',
              size: 1,
            ),
        ],
      ),
      size: const Size(1200, 400),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('40 files will be imported'), findsOneWidget);
    final importButton = find.widgetWithText(ArDriveButtonNew, 'Import');
    expect(importButton, findsOneWidget);
    expect(tester.getBottomRight(importButton).dy, lessThanOrEqualTo(400));
  });
}
