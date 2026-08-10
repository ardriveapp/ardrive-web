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

  FutureOr<void> abortDownload() {}
  FutureOr<void> retryDownload() {}
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
  if (error is DownloadNetworkException ||
      error is DownloadStalledException ||
      // The transport could not be picked up where it left off. Retrying
      // starts a clean download from byte 0, which is exactly the action the
      // network failure dialog offers.
      error is DownloadResumeNotSupportedException) {
    return FileDownloadFailureReason.networkConnectionError;
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
