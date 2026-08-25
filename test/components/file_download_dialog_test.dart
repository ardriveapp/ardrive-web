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
/// The warning triangle, which only the outcomes that really are a problem are
/// allowed to wear.
final Finder _alertIcon = find.byWidgetPredicate(
  (widget) => widget is ArDriveIcon && widget.icon == ArDriveIconsData.triangle,
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
      expect(find.text('DONE'), findsNothing);
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

        expect(find.text('Download finished!'), findsOneWidget,
            reason: 'for $verdict');
        expect(find.text('holiday.mp4'), findsOneWidget, reason: 'for $verdict');
        expect(find.text('DONE'), findsOneWidget, reason: 'for $verdict');

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
      expect(find.text('Download finished!'), findsNothing);
      expect(find.textContaining('holiday.mp4'), findsOneWidget);
      expect(find.textContaining('Delete it'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('a failed verdict does not look like the success it replaces',
        (tester) async {
      // Every ArDrive modal wears the same red strip, so the words were the
      // only thing telling this outcome apart from "Download finished!". The
      // alert icon beside the title is what carries it at a glance.
      await pumpState(
        tester,
        const FileDownloadFinishedWithSuccess(
          fileName: 'holiday.mp4',
          integrity: DataItemIntegrityVerdict.failed,
        ),
      );

      expect(_alertIcon, findsOneWidget);
    });

    testWidgets('neither harmless verdict borrows the alert icon',
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

        expect(_alertIcon, findsNothing, reason: '$verdict');
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

    testWidgets('the stall shows in the bar and not only in the word above it',
        (tester) async {
      Color fill() => tester
          .widget<ArDriveProgressBar>(find.byType(ArDriveProgressBar))
          .indicatorColor!;

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
        tester.getTopLeft(find.byType(ArDriveProgressBar)).dx,
        tester.getTopLeft(find.text('holiday.mp4')).dx,
      );
    });

    testWidgets('the reading is not jammed against the bar', (tester) async {
      await pumpState(tester, downloading);

      final barRight = tester.getTopRight(find.byType(ArDriveProgressBar)).dx;
      final readingLeft = tester.getTopLeft(find.text('62%')).dx;

      expect(readingLeft - barRight, greaterThanOrEqualTo(8));
    });
  });
}
