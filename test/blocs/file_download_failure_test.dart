import 'package:ardrive/blocs/file_download/file_download_cubit.dart';
import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/download/download_exceptions.dart';
import 'package:ardrive/download/download_policy.dart';
import 'package:flutter_test/flutter_test.dart';

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

    test('a resume that cannot be spliced is a network problem, and retrying '
        'from zero is the fix the dialog already offers', () {
      expect(
        classifyDownloadError(
            const DownloadResumeNotSupportedException(txId, 1232, 200)),
        FileDownloadFailureReason.networkConnectionError,
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
}
