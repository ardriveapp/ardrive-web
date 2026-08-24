import 'dart:async';

import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/arfs/repository/arfs_repository.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/download/download_exceptions.dart';
import 'package:ardrive/download/download_policy.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/utils/logger.dart';
// Only the verdict types: `ardrive_crypto` also exports a `Cipher`, which
// `package:cryptography` below already defines.
import 'package:ardrive_crypto/ardrive_crypto.dart'
    show DataItemIntegrityResult, DataItemIntegrityVerdict;
import 'package:ardrive_io/ardrive_io.dart' as io;
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'file_download_state.dart';
part 'personal_file_download_cubit.dart';
part 'shared_file_download_cubit.dart';

/// [FileDownloadCubit] is the abstract superclass for [Cubit]s that include
/// logic for download user files.
abstract class FileDownloadCubit extends Cubit<FileDownloadState> {
  FileDownloadCubit(super.state);

  StreamSubscription<DownloadResumeEvent>? _resumeSubscription;

  FutureOr<void> abortDownload() {}
  FutureOr<void> retryDownload() {}

  /// How long the terminal state may wait on a verdict.
  ///
  /// [ArDriveDownloader.integrity] is documented to always complete, and every
  /// path in the downloader settles it. This is the guard for the one that is
  /// ever missed: the dialog is a `barrierDismissible: false` modal whose only
  /// escape from "checking" is the state after it, so a verdict that never
  /// arrives would trap the user in a download that has, in fact, finished.
  static const _verdictTimeout = Duration(seconds: 20);

  /// How long a verdict may take before the user is told one is being waited
  /// on. Short enough to appear promptly on the paths that are genuinely slow,
  /// long enough that an already-settled verdict never shows the step at all.
  static const _verdictAnnounceDelay = Duration(milliseconds: 250);

  /// Turns [downloader]'s mid-stream recoveries into something the user can
  /// see.
  ///
  /// A download that loses its connection and resumes keeps the same progress
  /// number for as long as it takes to reconnect — nothing is arriving, so
  /// nothing moves. Without this the bar is simply frozen, which is what a
  /// hung app looks like.
  ///
  /// Only a determinate progress bar can look frozen, so only
  /// [FileDownloadWithProgress] is upgraded; the earlier states already show an
  /// indeterminate spinner that keeps turning. The flag clears on its own,
  /// because the next progress tick builds a fresh state.
  @protected
  void watchForReconnects(ArDriveDownloader downloader) {
    _resumeSubscription ??= downloader.resumeEvents.listen(
      (event) {
        // Cancelling a subscription does not un-queue what it has already been
        // handed, and `emit` after `close` throws.
        if (isClosed) return;

        logger.d('Download is reconnecting: $event');

        final current = state;
        if (current is FileDownloadWithProgress && !current.isReconnecting) {
          emit(current.asReconnecting());
        }
      },
      // Nothing else observes this stream, and a download must not fail
      // because the commentary on it did.
      onError: (Object e) =>
          logger.d('Could not report a download reconnect: $e'),
    );
  }

  /// Ends a download whose bytes are all saved, with what the integrity check
  /// made of them.
  ///
  /// Call this from the progress stream's `onDone` and **never before**: the
  /// save must not wait on a verdict, so the verdict is collected only once
  /// there is nothing left for it to hold up.
  @protected
  Future<void> emitFinishedWithIntegrity({
    required ArDriveDownloader downloader,
    required String fileName,
  }) async {
    if (isClosed || state is FileDownloadAborted) return;

    DataItemIntegrityResult result;

    final verdict = downloader.integrity;

    // Announce the check only if it is actually going to take a moment.
    //
    // Every verdict this app can now reach is settled before the last byte is
    // written: AES-GCM is MAC-checked during the download, and everything else
    // has no check to run. Emitting "Checking this file" unconditionally meant
    // a modal that appeared and replaced itself in the same breath - a flash
    // of a step that never happened. The state is kept rather than deleted
    // because it is correct the moment a caller asks for `verifyIntegrity`
    // again, and then it is worth showing.
    var answered = false;
    // Swallowed here and read properly below: this is only asking "has it
    // landed yet", and `integrity` is documented never to complete with an
    // error anyway.
    final settled = verdict.then<void>(
      (_) => answered = true,
      onError: (Object _) => answered = true,
    );
    await Future.any<void>([
      settled,
      Future<void>.delayed(_verdictAnnounceDelay),
    ]);

    if (isClosed || state is FileDownloadAborted) return;

    if (!answered) {
      emit(FileDownloadVerifying(fileName: fileName));
    }

    try {
      result = await verdict.timeout(
        _verdictTimeout,
        onTimeout: () => const DataItemIntegrityResult.notVerified(
          'The integrity check did not answer in time',
        ),
      );
    } catch (e) {
      // [ArDriveDownloader.integrity] is documented never to complete with an
      // error, but a verdict that cannot be read is precisely what
      // `notVerified` is for, and a download that finished must never be
      // reported as failed because its commentary threw.
      logger.d('Could not read the integrity verdict for $fileName: $e');
      result = DataItemIntegrityResult.notVerified(
        'The integrity check could not be read: $e',
      );
    }

    if (isClosed || state is FileDownloadAborted) return;

    logger.d('Integrity verdict for $fileName: $result');

    emit(FileDownloadFinishedWithSuccess(
      fileName: fileName,
      integrity: result.verdict,
    ));
  }

  @override
  Future<void> close() {
    unawaited(_resumeSubscription?.cancel());
    _resumeSubscription = null;

    return super.close();
  }
}

/// What the UI should say about [error].
///
/// Shared by both download cubits on purpose. They kept identical private
/// copies, which is how a typed exception ends up on screen as "something went
/// wrong": it only has to be forgotten in one of them.
@visibleForTesting
FileDownloadFailureReason classifyDownloadError(Object error) {
  if (error is DownloadFileNotFoundException) {
    return FileDownloadFailureReason.fileNotFound;
  }
  if (error is DownloadRateLimitException) {
    return FileDownloadFailureReason.rateLimited;
  }
  if (error is DownloadNetworkException || error is DownloadStalledException) {
    return FileDownloadFailureReason.networkConnectionError;
  }
  // The transport could not be picked up where it left off, so the part that
  // had already arrived is gone. Retrying is still the fix - it just starts
  // from byte 0, and the dialog has to say so rather than let "try again" imply
  // the download carries on from where the bar stopped.
  if (error is DownloadResumeNotSupportedException) {
    return FileDownloadFailureReason.downloadMustRestart;
  }
  if (error is DownloadTooLargeToAuthenticateException) {
    return FileDownloadFailureReason.fileTooLargeToVerify;
  }
  // A file that failed its MAC check is the one failure that must never be
  // offered a retry: the bytes are what they are, and the retryable dialog
  // would invite the user to fetch them again forever.
  if (error is DownloadIntegrityException) {
    return FileDownloadFailureReason.integrityCheckFailed;
  }
  return FileDownloadFailureReason.unknownError;
}

/// The failure to report when [limit] rules out saving a single file of
/// [sizeBytes], or `null` when it does not.
///
/// [DownloadPolicy.singleFileLimit] is the one place that decides; this only
/// names which of the two "too big" messages fits the rule that produced it,
/// so that a mobile ceiling is never explained as a browser limitation.
@visibleForTesting
FileDownloadFailureReason? singleFileLimitFailure(
  DownloadSizeLimit limit,
  int sizeBytes,
) {
  if (limit.allows(sizeBytes)) return null;

  switch (limit.source) {
    case DownloadSizeLimitSource.mobile:
      return FileDownloadFailureReason.fileAboveLimit;
    case DownloadSizeLimitSource.safari:
    case DownloadSizeLimitSource.firefox:
    case DownloadSizeLimitSource.web:
    case DownloadSizeLimitSource.unknownPlatform:
    case DownloadSizeLimitSource.none:
      return FileDownloadFailureReason.browserDoesNotSupportLargeDownloads;
  }
}
