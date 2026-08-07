import 'package:ardrive/blocs/file_download/file_download_cubit.dart';
import 'package:ardrive/components/file_download_dialog.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart'
    show DataItemIntegrityVerdict;
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class MockFileDownloadCubit extends MockCubit<FileDownloadState>
    implements FileDownloadCubit {}

/// What the download modal says about integrity and about reconnecting.
///
/// The downloader has reached a three-valued verdict on every download since
/// Phase 2 and told nobody. These are the assertions that a verdict is on
/// screen at all - and, just as importantly, that the two harmless ones do not
/// read like the harmful one.
void main() {
  Widget wrap(Widget child) {
    return ArDriveTheme(
      themeData: lightTheme(),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', '')],
        home: Scaffold(body: child),
      ),
    );
  }

  Future<void> pumpState(WidgetTester tester, FileDownloadState state) async {
    // Room for the whole modal, so nothing here is about layout.
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final cubit = MockFileDownloadCubit();

    whenListen(
      cubit,
      const Stream<FileDownloadState>.empty(),
      initialState: state,
    );

    await tester.pumpWidget(
      wrap(
        BlocProvider<FileDownloadCubit>.value(
          value: cubit,
          child: const FileDownloadDialog(),
        ),
      ),
    );
    await tester.pump();
  }

  group('the verifying state', () {
    testWidgets('says the file is already saved while the check runs',
        (tester) async {
      await pumpState(
        tester,
        const FileDownloadVerifying(fileName: 'holiday.mp4'),
      );

      expect(find.text('Checking this file...'), findsOneWidget);
      expect(find.text('holiday.mp4'), findsOneWidget);
      // The modal must never suggest the save is waiting on the check. It is
      // not, deliberately: the bytes are on disk before this state exists.
      expect(find.textContaining('has been saved'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('offers nothing to press, because there is nothing to decide',
        (tester) async {
      await pumpState(
        tester,
        const FileDownloadVerifying(fileName: 'holiday.mp4'),
      );

      expect(find.text('Cancel'), findsNothing);
      expect(find.text('DONE'), findsNothing);
    });
  });

  group('the verdict on a finished download', () {
    testWidgets('a verified file gets one quiet affirmative', (tester) async {
      await pumpState(
        tester,
        const FileDownloadFinishedWithSuccess(
          fileName: 'holiday.mp4',
          integrity: DataItemIntegrityVerdict.verified,
        ),
      );

      expect(find.text('Download finished!'), findsOneWidget);
      expect(find.text('holiday.mp4'), findsOneWidget);
      expect(
        find.text('This file matches what was originally uploaded.'),
        findsOneWidget,
      );
      expect(find.text('DONE'), findsOneWidget);
    });

    testWidgets('an unchecked file is told so without being alarmed',
        (tester) async {
      await pumpState(
        tester,
        const FileDownloadFinishedWithSuccess(
          fileName: 'holiday.mp4',
          integrity: DataItemIntegrityVerdict.notVerified,
        ),
      );

      // Still a finished download, because it is one. A resumed download and a
      // file signed with a wallet ArDrive cannot check both land here, and
      // both are perfectly good files.
      expect(find.text('Download finished!'), findsOneWidget);
      expect(find.textContaining('couldn’t check this file'), findsOneWidget);
      expect(find.textContaining('doesn’t mean anything is wrong'),
          findsOneWidget);

      // None of the language reserved for a file that really is wrong.
      expect(find.textContaining('doesn’t match'), findsNothing);
      expect(find.textContaining('Delete it'), findsNothing);
    });

    testWidgets('a failed verdict takes over the modal and says what to do',
        (tester) async {
      await pumpState(
        tester,
        const FileDownloadFinishedWithSuccess(
          fileName: 'holiday.mp4',
          integrity: DataItemIntegrityVerdict.failed,
        ),
      );

      expect(find.text('This file doesn’t match the original'), findsOneWidget);
      // Not a footnote under a congratulation.
      expect(find.text('Download finished!'), findsNothing);
      expect(find.textContaining('holiday.mp4'), findsOneWidget);
      expect(find.textContaining('Delete it'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('a download that was never checked says nothing about checks',
        (tester) async {
      // The mobile public download hands the transfer to the platform and
      // never sees the bytes. Reporting "could not be checked" would name the
      // absence of something nobody attempted.
      await pumpState(
        tester,
        const FileDownloadFinishedWithSuccess(fileName: 'holiday.mp4'),
      );

      expect(find.text('Download finished!'), findsOneWidget);
      expect(find.text('holiday.mp4'), findsOneWidget);
      expect(find.textContaining('originally uploaded'), findsNothing);
      expect(find.textContaining('couldn’t check'), findsNothing);
    });
  });

  group('reconnecting', () {
    const downloading = FileDownloadWithProgress(
      fileName: 'holiday.mp4',
      progress: 62,
      fileSize: 5000000,
      contentType: 'video/mp4',
    );

    testWidgets('a healthy download says it is downloading', (tester) async {
      await pumpState(tester, downloading);

      expect(find.text('Downloading'), findsOneWidget);
      expect(find.text('Reconnecting...'), findsNothing);
      expect(find.text('62%'), findsOneWidget);
    });

    testWidgets('a stalled one says it is reconnecting, and keeps its place',
        (tester) async {
      await pumpState(tester, downloading.asReconnecting());

      expect(find.text('Reconnecting...'), findsOneWidget);
      expect(find.text('Downloading'), findsNothing);
      // The bar has not moved and must not pretend otherwise: the progress
      // already made is exactly what a resume preserves.
      expect(find.text('62%'), findsOneWidget);
      expect(find.byType(ArDriveProgressBar), findsOneWidget);
      // Cancelling a download that is trying to recover is still an option.
      expect(find.text('Cancel'), findsOneWidget);
    });
  });
}
