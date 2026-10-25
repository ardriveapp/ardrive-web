import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final strings = lookupAppLocalizations(const Locale('en'));

  group('the multi-file download dialog', () {
    // The dialog shows this title for a moment even when nothing was skipped,
    // before it closes, and it used to read "with 0 skipped file(s)".
    test('says nothing about skipping when nothing was skipped', () {
      expect(
        strings.multiDownloadCompleteWithSkippedFiles(0),
        'Download complete',
      );
    });

    test('counts skipped files in plain words', () {
      expect(
        strings.multiDownloadCompleteWithSkippedFiles(1),
        'Download complete, 1 file skipped',
      );
      expect(
        strings.multiDownloadCompleteWithSkippedFiles(3),
        'Download complete, 3 files skipped',
      );
    });

    test('says no "file(s)" anywhere', () {
      for (final text in [
        strings.multiDownloadDownloadingFilesProgress(3, 10),
        strings.multiDownloadErrorTryAgain,
        strings.fileFailedToDownloadFileAbovePublicLimit,
      ]) {
        expect(text, isNot(contains('(s)')));
      }
      expect(
        strings.multiDownloadDownloadingFilesProgress(3, 10),
        'Downloading file 3 of 10',
      );
    });
  });
}
