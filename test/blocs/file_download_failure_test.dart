import 'package:ardrive/blocs/file_download/file_download_cubit.dart';
import 'package:ardrive/components/file_download_dialog.dart';
import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/download/download_exceptions.dart';
import 'package:ardrive/download/download_policy.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class MockFileDownloadCubit extends MockCubit<FileDownloadState>
    implements FileDownloadCubit {}

/// The warning triangle, which only the failures that really are alarming are
/// allowed to wear.
final Finder _alertIcon = find.byWidgetPredicate(
  (widget) => widget is ArDriveIcon && widget.icon == ArDriveIconsData.triangle,
);

/// What the user is told when a download fails.
///
/// Both cubits used to keep private copies of this mapping, and both had
/// fallen behind the exceptions the download path throws: a file the code had
/// diagnosed precisely came out on screen as "something went wrong".
void main() {
  const txId = 'a-transaction-id';

  group('classifyDownloadError', () {
    test('names the gateway failures', () {
      expect(
        classifyDownloadError(const DownloadFileNotFoundException(txId)),
        FileDownloadFailureReason.fileNotFound,
      );
      expect(
        classifyDownloadError(const DownloadRateLimitException(txId)),
        FileDownloadFailureReason.rateLimited,
      );
      expect(
        classifyDownloadError(const DownloadNetworkException(txId, 'no route')),
        FileDownloadFailureReason.networkConnectionError,
      );
      expect(
        classifyDownloadError(
            const DownloadStalledException(txId, Duration(seconds: 60))),
        FileDownloadFailureReason.networkConnectionError,
      );
    });

    test('a resume that cannot be spliced is named as a restart, not as a '
        'generic network problem', () {
      // Retrying *is* the fix, so this is not the integrity dialog's dead end.
      // But the bytes already delivered are gone, so it is not the network
      // dialog either: that one offers "Try Again", which to somebody watching
      // a bar sit at 80% promises the remaining 20%.
      expect(
        classifyDownloadError(
            const DownloadResumeNotSupportedException(txId, 1232, 200)),
        FileDownloadFailureReason.downloadMustRestart,
      );
    });

    test('a body larger than the file claimed is reported as a size problem, '
        'not as an unknown one', () {
      expect(
        classifyDownloadError(
            const DownloadTooLargeToAuthenticateException(txId, 1 << 30, 1)),
        FileDownloadFailureReason.fileTooLargeToVerify,
      );
    });

    test('a file that failed its authentication check is named as one, and '
        'never offered a retry', () {
      // The retryable dialog is what the fallback reason renders, and it is
      // exactly wrong here: the bytes are what they are, so "Try again" is an
      // invitation to fetch them and fail the same check for ever. Nothing was
      // written either (§3.1), which the copy for this reason has to say.
      expect(
        classifyDownloadError(
          const DownloadIntegrityException(
            txId,
            'The file did not pass its AES-GCM authentication check',
          ),
        ),
        FileDownloadFailureReason.integrityCheckFailed,
      );
    });

    test('anything genuinely unrecognised still falls back', () {
      expect(
        classifyDownloadError(Exception('something else entirely')),
        FileDownloadFailureReason.unknownError,
      );
    });
  });

  group('singleFileLimitFailure', () {
    test('a file within the ceiling is not a failure', () {
      expect(
        singleFileLimitFailure(
          DownloadSizeLimit(publicDownloadSafariSizeLimit,
              DownloadSizeLimitSource.safari),
          publicDownloadSafariSizeLimit,
        ),
        isNull,
      );
      expect(
        singleFileLimitFailure(const DownloadSizeLimit.none(), 1 << 40),
        isNull,
      );
    });

    test('Safari is explained as a browser limitation', () {
      expect(
        singleFileLimitFailure(
          DownloadSizeLimit(publicDownloadSafariSizeLimit,
              DownloadSizeLimitSource.safari),
          publicDownloadSafariSizeLimit + 1,
        ),
        FileDownloadFailureReason.browserDoesNotSupportLargeDownloads,
      );
    });

    test('a phone is not explained as a browser limitation', () {
      expect(
        singleFileLimitFailure(
          DownloadSizeLimit(privateDownloadMobileSizeLimit,
              DownloadSizeLimitSource.mobile),
          privateDownloadMobileSizeLimit + 1,
        ),
        FileDownloadFailureReason.fileAboveLimit,
      );
    });
  });

  group('what the dialog does with a reason', () {
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

    Future<void> pumpFailure(
      WidgetTester tester,
      FileDownloadFailureReason reason,
    ) async {
      // Room for the whole modal, so nothing here is about layout.
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final cubit = MockFileDownloadCubit();

      whenListen(
        cubit,
        const Stream<FileDownloadState>.empty(),
        initialState: FileDownloadFailure(reason),
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

    testWidgets('offers a retry for a failure that a retry could fix',
        (tester) async {
      await pumpFailure(tester, FileDownloadFailureReason.unknownError);

      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('never offers a retry for a file that failed its integrity '
        'check, and says nothing was saved', (tester) async {
      await pumpFailure(tester, FileDownloadFailureReason.integrityCheckFailed);

      // The whole point of the typed reason: these bytes will fail the same
      // check every time, so the retryable dialog would be an invitation to
      // download them for ever.
      expect(find.text('Try Again'), findsNothing);
      expect(find.text('OK'), findsOneWidget);
      expect(find.textContaining('nothing was saved'), findsOneWidget);
      // Corrupted bytes are not a routine transport hiccup, and the modal has
      // to look like it: same alert treatment as the post-save verdict.
      expect(_alertIcon, findsOneWidget);
    });

    testWidgets('a download that cannot be resumed offers a restart, and does '
        'not call it trying again', (tester) async {
      await pumpFailure(tester, FileDownloadFailureReason.downloadMustRestart);

      expect(find.text('Start Over'), findsOneWidget);
      // "Try Again" next to a bar that stopped at 80% promises the last 20%,
      // and this is precisely the failure where that cannot be delivered.
      expect(find.text('Try Again'), findsNothing);
      expect(find.textContaining('from the beginning'), findsOneWidget);
      // A dropped connection is an inconvenience, not an alarm. Spending the
      // alert icon here would spend it everywhere.
      expect(_alertIcon, findsNothing);
    });
  });
}
