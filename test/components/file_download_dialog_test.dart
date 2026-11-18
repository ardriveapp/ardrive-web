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
/// The error notice, which only the outcomes that really are a problem are
/// allowed to carry.
final Finder _errorNotice = find.byWidgetPredicate(
  (widget) => widget is ArDriveNotice && widget.type == ArDriveNoticeType.error,
);

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
      expect(find.text('Done'), findsNothing);
    });
  });

  group('the verdict on a finished download', () {
    testWidgets('a finished download says it finished, and no more',
        (tester) async {
      // Every verdict reads the same here, because none of them is worth a
      // line. "Verified" claimed the bytes matched what the uploader signed,
      // which is the data item signature and is not fetched on this path. What
      // it really meant was that the AES-GCM MAC checked out - a real check,
      // but one a user can never learn anything from: a MAC that fails throws
      // out of the download, so this dialog is only ever reached when it
      // passed.
      for (final verdict in DataItemIntegrityVerdict.values) {
        if (verdict == DataItemIntegrityVerdict.failed) continue;

        await pumpState(
          tester,
          FileDownloadFinishedWithSuccess(
            fileName: 'holiday.mp4',
            integrity: verdict,
          ),
        );

        expect(find.text('Download finished'), findsOneWidget,
            reason: 'for $verdict');
        expect(find.text('holiday.mp4'), findsOneWidget,
            reason: 'for $verdict');
        expect(find.text('Done'), findsOneWidget, reason: 'for $verdict');

        // No claim about the bytes, in either direction.
        expect(find.textContaining('matches what was originally'), findsNothing,
            reason: 'for $verdict');
        expect(find.textContaining('couldn’t check'), findsNothing,
            reason: 'for $verdict');
      }
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
      expect(find.text('Download finished'), findsNothing);
      expect(find.textContaining('holiday.mp4'), findsOneWidget);
      expect(find.textContaining('Delete it'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('a failed verdict does not look like the success it replaces',
        (tester) async {
      // The words say what happened; the error notice is what carries it at a
      // glance.
      await pumpState(
        tester,
        const FileDownloadFinishedWithSuccess(
          fileName: 'holiday.mp4',
          integrity: DataItemIntegrityVerdict.failed,
        ),
      );

      expect(_errorNotice, findsOneWidget);
    });

    testWidgets('neither harmless verdict borrows the error notice',
        (tester) async {
      for (final verdict in [
        DataItemIntegrityVerdict.verified,
        DataItemIntegrityVerdict.notVerified,
      ]) {
        await pumpState(
          tester,
          FileDownloadFinishedWithSuccess(
            fileName: 'holiday.mp4',
            integrity: verdict,
          ),
        );

        expect(_errorNotice, findsNothing, reason: '$verdict');
      }
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

      expect(find.text('Download finished'), findsOneWidget);
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
      expect(find.byType(ArDriveLinearProgress), findsOneWidget);
      // Cancelling a download that is trying to recover is still an option.
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('the stall shows in the bar and not only in the word above it',
        (tester) async {
      // The colour the bar is drawn in, whether it was passed or defaulted.
      Color fill() => tester
          .widget<LinearProgressIndicator>(find.descendant(
            of: find.byType(ArDriveLinearProgress),
            matching: find.byType(LinearProgressIndicator),
          ))
          .color!;

      await pumpState(tester, downloading);
      final moving = fill();

      await pumpState(tester, downloading.asReconnecting());
      final stalled = fill();

      // Not an indeterminate sweep - 62% is true and a resume keeps it. The
      // bar goes inactive instead, so a glance at it is enough to tell that
      // nothing is arriving.
      expect(stalled, isNot(moving));
    });
  });

  group('the progress layout', () {
    const downloading = FileDownloadWithProgress(
      fileName: 'holiday.mp4',
      progress: 62,
      fileSize: 5000000,
      contentType: 'video/mp4',
    );

    testWidgets('the bar starts where the text it measures starts',
        (tester) async {
      await pumpState(tester, downloading);

      // The bar used to begin at the modal's content edge while everything it
      // describes began 56px further in, past the type icon.
      expect(
        tester.getTopLeft(find.byType(ArDriveLinearProgress)).dx,
        tester.getTopLeft(find.text('holiday.mp4')).dx,
      );
    });

    testWidgets('the reading is not jammed against the bar', (tester) async {
      await pumpState(tester, downloading);

      final barRight =
          tester.getTopRight(find.byType(ArDriveLinearProgress)).dx;
      final readingLeft = tester.getTopLeft(find.text('62%')).dx;

      expect(readingLeft - barRight, greaterThanOrEqualTo(8));
    });
  });

  group('the large-file warning', () {
    testWidgets('has Cancel first and Download last, as the primary',
        (tester) async {
      await pumpState(tester, const FileDownloadWarning());

      expect(find.text('Download a large file'), findsOneWidget);
      expect(find.text('Warning'), findsNothing);
      expect(find.byType(ArDriveNotice), findsOneWidget);

      final buttons = tester
          .widgetList<ArDriveButtonNew>(find.byType(ArDriveButtonNew))
          .toList();
      expect(buttons.map((b) => b.text), ['Cancel', 'Download']);
      expect(buttons.first.variant, ButtonVariant.secondary);
      expect(buttons.last.variant, ButtonVariant.primary);
    });
  });

  group('failures that only close', () {
    testWidgets(
        'a file that is too large is named by what happened, with Close',
        (tester) async {
      await pumpState(
        tester,
        const FileDownloadFailure(FileDownloadFailureReason.fileAboveLimit),
      );

      expect(
          find.text('This file is too large to download here'), findsOneWidget);
      expect(find.text('Warning'), findsNothing);
      expect(find.text('OK'), findsNothing);
      expect(
        tester
            .widget<ArDriveButtonNew>(
                find.widgetWithText(ArDriveButtonNew, 'Close'))
            .variant,
        ButtonVariant.secondary,
      );
    });
  });

  group('the states share one width', () {
    testWidgets(
        'the wait, the progress and the check are as wide as each other',
        (tester) async {
      await pumpState(
        tester,
        const FileDownloadInProgress(
            fileName: 'holiday.mp4', totalByteCount: 5),
      );
      final inProgress = tester.getSize(find.byType(ArDriveStandardModalNew));

      await pumpState(
        tester,
        const FileDownloadWithProgress(
          fileName: 'holiday.mp4',
          progress: 62,
          fileSize: 5000000,
          contentType: 'video/mp4',
        ),
      );
      final progress = tester.getSize(find.byType(ArDriveStandardModalNew));

      await pumpState(
        tester,
        const FileDownloadVerifying(fileName: 'holiday.mp4'),
      );
      final verifying = tester.getSize(find.byType(ArDriveStandardModalNew));

      expect(progress.width, inProgress.width);
      expect(verifying.width, inProgress.width);
    });
  });
}
