import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/arfs/repository/arfs_repository.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
// Only the verdict enum: `ardrive_crypto` also exports a `Cipher`, which
// `package:cryptography` below already defines.
import 'package:ardrive_crypto/ardrive_crypto.dart'
    show DataItemIntegrityVerdict;
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> promptToDownloadProfileFile({
  required BuildContext context,
  required FileDataTableItem file,
}) {
  final ARFSFileEntity arfsFile =
      ARFSFactory().getARFSFileFromFileDataItemTable(file);

  final profileState = context.read<ProfileCubit>().state;
  final arweave = context.read<ArweaveService>();
  final cipherKey =
      profileState is ProfileLoggedIn ? profileState.user.cipherKey : null;
  final cubit = ProfileFileDownloadCubit(
    crypto: ArDriveCrypto(),
    arfsRepository: ARFSRepository(
      context.read<DriveDao>(),
      ARFSFactory(),
    ),
    arDriveDownloader: ArDriveDownloader(
      ardriveIo: ArDriveIO(),
      ioFileAdapter: IOFileAdapter(),
      arweave: arweave,
    ),
    downloader: ArDriveMobileDownloader(),
    file: arfsFile,
    driveDao: context.read<DriveDao>(),
    arweave: arweave,
  )..verifyUploadLimitationsAndDownload(cipherKey);
  return showArDriveDialog(
    context,
    barrierDismissible: false,
    content: BlocProvider<FileDownloadCubit>.value(
      value: cubit,
      child: const FileDownloadDialog(),
    ),
  );
}

Future<void> promptToDownloadFileRevision({
  required BuildContext context,
  required ARFSFileEntity revision,
}) {
  final ARFSFileEntity arfsFile = revision;

  final profileState = context.read<ProfileCubit>().state;

  final arweave = context.read<ArweaveService>();

  final cipherKey =
      profileState is ProfileLoggedIn ? profileState.user.cipherKey : null;
  final cubit = ProfileFileDownloadCubit(
    crypto: ArDriveCrypto(),
    arfsRepository: ARFSRepository(
      context.read<DriveDao>(),
      ARFSFactory(),
    ),
    arDriveDownloader: ArDriveDownloader(
      ardriveIo: ArDriveIO(),
      ioFileAdapter: IOFileAdapter(),
      arweave: arweave,
    ),
    downloader: ArDriveMobileDownloader(),
    file: arfsFile,
    driveDao: context.read<DriveDao>(),
    arweave: arweave,
  )..verifyUploadLimitationsAndDownload(cipherKey);

  return showArDriveDialog(
    context,
    barrierDismissible: false,
    content: BlocProvider<FileDownloadCubit>.value(
      value: cubit,
      child: const FileDownloadDialog(),
    ),
  );
}

Future<void> promptToDownloadSharedFile({
  required BuildContext context,
  SecretKey? fileKey,
  required ARFSFileEntity revision,
  String? cipher,
  String? cipherIv,
  bool publicIsUnconfirmed = false,
}) {
  final cubit = SharedFileDownloadCubit(
    arDriveDownloader: ArDriveDownloader(
      ardriveIo: ArDriveIO(),
      ioFileAdapter: IOFileAdapter(),
      arweave: context.read<ArweaveService>(),
    ),
    crypto: ArDriveCrypto(),
    revision: revision,
    fileKey: fileKey,
    cipher: cipher,
    cipherIv: cipherIv,
    publicIsUnconfirmed: publicIsUnconfirmed,
    arweave: context.read<ArweaveService>(),
  );
  return showArDriveDialog(
    context,
    barrierDismissible: false,
    content: BlocProvider<FileDownloadCubit>.value(
      value: cubit,
      child: const FileDownloadDialog(),
    ),
  );
}

class FileDownloadDialog extends StatelessWidget {
  const FileDownloadDialog({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<FileDownloadCubit, FileDownloadState>(
        listener: (context, state) async {
          if (state is FileDownloadSuccess) {
            final ArDriveIO io = ArDriveIO();

            final file = await IOFile.fromData(
              state.bytes,
              name: state.fileName,
              lastModifiedDate: state.lastModified,
            );

            // Close modal when save file
            io.saveFile(file).then((value) => Navigator.pop(context));
          }
        },
        builder: (context, state) {
          if (state is FileDownloadStarting) {
            return _downloadStartingDialog(context);
          } else if (state is FileDownloadVerifying) {
            return _downloadVerifyingDialog(context, state);
          } else if (state is FileDownloadFinishedWithSuccess) {
            return downloadFinishedWithSuccessDialog(context, state);
          } else if (state is FileDownloadWithProgress) {
            return _downloadingFileWithProgressDialog(context, state);
          } else if (state is FileDownloadInProgress) {
            return _fileDownloadInProgressDialog(context, state);
          } else if (state is FileDownloadFailure) {
            switch (state.reason) {
              case FileDownloadFailureReason.unknownError:
                return _retryableFailureDialog(
                  context,
                  title: appLocalizationsOf(context).fileFailedToDownload,
                  description:
                      appLocalizationsOf(context).tryAgainDownloadingFile,
                );
              case FileDownloadFailureReason.networkConnectionError:
                return _retryableFailureDialog(
                  context,
                  title: appLocalizationsOf(context).downloadNetworkError,
                  description: appLocalizationsOf(context)
                      .downloadNetworkErrorDescription,
                );
              case FileDownloadFailureReason.rateLimited:
                return _retryableFailureDialog(
                  context,
                  title: appLocalizationsOf(context).downloadRateLimited,
                  description: appLocalizationsOf(context)
                      .downloadRateLimitedDescription,
                );
              case FileDownloadFailureReason.fileNotFound:
                return _modalWrapper(
                  title: appLocalizationsOf(context).downloadFileNotFound,
                  description: appLocalizationsOf(context)
                      .downloadFileNotFoundDescription,
                  actions: [
                    ModalAction.close(
                      action: () => Navigator.pop(context),
                      title: appLocalizationsOf(context).close,
                    ),
                  ],
                );
              case FileDownloadFailureReason.integrityCheckFailed:
                // Deliberately not retryable, and deliberately not phrased as
                // a network problem: the bytes arrived, they simply are not
                // the bytes that were signed. Nothing was saved.
                return _integrityFailureDialog(
                  context,
                  title: appLocalizationsOf(context).downloadIntegrityFailed,
                  description: appLocalizationsOf(context)
                      .downloadIntegrityFailedDescription,
                  onDismiss: () => Navigator.pop(context),
                );
              case FileDownloadFailureReason.downloadMustRestart:
                // Retryable, and the retry works - but it starts from byte 0,
                // so the action must not be the same "Try Again" that every
                // other transport failure offers. A user watching a bar reach
                // 80% and then reading "Try Again" reasonably expects the
                // remaining 20%.
                return _retryableFailureDialog(
                  context,
                  title: appLocalizationsOf(context).downloadMustRestart,
                  description: appLocalizationsOf(context)
                      .downloadMustRestartDescription,
                  retryTitle: appLocalizationsOf(context).downloadStartOver,
                );
              case FileDownloadFailureReason.encryptedWithoutKey:
                // Not retryable, and deliberately not phrased as a failure of
                // the file: the bytes are fine and fetching them again cannot
                // supply a key the recipient never had.
                return _modalWrapper(
                  title: appLocalizationsOf(context).downloadNeedsKey,
                  description:
                      appLocalizationsOf(context).downloadNeedsKeyDescription,
                  actions: [
                    ModalAction.close(
                      action: () => Navigator.pop(context),
                      title: appLocalizationsOf(context).close,
                    ),
                  ],
                );
              case FileDownloadFailureReason.fileAboveLimit:
                return _fileDownloadFailedDueToFileAbovePrivateLimit(context);
              case FileDownloadFailureReason
                    .browserDoesNotSupportLargeDownloads:
              // Same message: from the user's side both mean "this file is
              // larger than this download can handle, and nothing was saved".
              case FileDownloadFailureReason.fileTooLargeToVerify:
                return _fileDownloadFailedDueToAboveBrowserLimit(context);
            }
          } else if (state is FileDownloadWarning) {
            return _warningToWaitDownloadFinishes(context);
          } else if (state is FileDownloadAborted) {
            return _fileDownloadAbortedDialog(context);
          } else {
            return const SizedBox();
          }
        },
      );

  ArDriveStandardModalNew _retryableFailureDialog(
    BuildContext context, {
    required String title,
    required String description,
    String? retryTitle,
  }) {
    return _modalWrapper(
      title: title,
      description: description,
      actions: [
        ModalAction.close(
          action: () => Navigator.pop(context),
          title: appLocalizationsOf(context).cancel,
        ),
        ModalAction(
          action: () => context.read<FileDownloadCubit>().retryDownload(),
          title: retryTitle ?? appLocalizationsOf(context).tryAgain,
        ),
      ],
    );
  }

  ArDriveStandardModalNew _fileDownloadFailedDueToFileAbovePrivateLimit(
      BuildContext context) {
    return _modalWrapper(
      title: appLocalizationsOf(context).downloadFileTooLargeTitle,
      description:
          appLocalizationsOf(context).fileFailedToDownloadFileAboveLimit,
      actions: [
        ModalAction.close(
          action: () => Navigator.pop(context),
          title: appLocalizationsOf(context).close,
        ),
      ],
    );
  }

  ArDriveStandardModalNew _fileDownloadFailedDueToAboveBrowserLimit(
      BuildContext context) {
    return _modalWrapper(
      title: appLocalizationsOf(context).downloadFileTooLargeTitle,
      description:
          appLocalizationsOf(context).fileFailedToDownloadFileAbovePublicLimit,
      actions: [
        ModalAction.close(
          action: () => Navigator.pop(context),
          title: appLocalizationsOf(context).close,
        ),
      ],
    );
  }

  ArDriveStandardModalNew _warningToWaitDownloadFinishes(BuildContext context) {
    return _modalWrapper(
      title: appLocalizationsOf(context).downloadLargeFileTitle,
      child: SizedBox(
        width: kMediumDialogWidth,
        child: ArDriveNotice(
          type: ArDriveNoticeType.warning,
          message: appLocalizationsOf(context).waitForDownload,
        ),
      ),
      actions: [
        ModalAction.close(
          action: () => Navigator.pop(context),
          title: appLocalizationsOf(context).cancel,
        ),
        ModalAction(
          action: () {
            final profileState = context.read<ProfileCubit>().state;

            final cipherKey = profileState is ProfileLoggedIn
                ? profileState.user.cipherKey
                : null;

            (context.read<FileDownloadCubit>() as ProfileFileDownloadCubit)
                .download(cipherKey);
          },
          title: appLocalizationsOf(context).download,
        ),
      ],
    );
  }

  ArDriveStandardModalNew _downloadStartingDialog(BuildContext context) {
    return _modalWrapper(
      title: appLocalizationsOf(context).downloadingFile,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(child: ArDriveSpinner(size: ArDriveSpinnerSize.large)),
        ],
      ),
      actions: [
        ModalAction.dismiss(
          action: () => Navigator.pop(context),
          title: appLocalizationsOf(context).cancel,
        ),
      ],
    );
  }

  ArDriveStandardModalNew _fileDownloadInProgressDialog(
      BuildContext context, FileDownloadInProgress state) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return _modalWrapper(
      title: appLocalizationsOf(context).downloadingFile,
      child: _fileRow(
        context,
        icon: ArDriveIcons.fileOutlined(size: 24),
        name: state.fileName,
        details: [
          Text(
            filesize(state.totalByteCount),
            style: ArDriveTypographyNew.of(context)
                .paragraphNormal(color: colorTokens.textMid),
          ),
        ],
        trailing: const ArDriveSpinner(),
      ),
      actions: [
        ModalAction.dismiss(
          action: () async {
            await context.read<FileDownloadCubit>().abortDownload();
            // ignore: use_build_context_synchronously
            Navigator.pop(context);
          },
          title: appLocalizationsOf(context).cancel,
        ),
      ],
    );
  }

  /// The one row every download state shows: the file's icon and name, a
  /// line or two under it, and what belongs at its end. Every state is the
  /// same width, so the dialog does not resize between them.
  Widget _fileRow(
    BuildContext context, {
    required Widget icon,
    required String name,
    required List<Widget> details,
    Widget? trailing,
  }) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    // A [Row] rather than a [ListTile]: everything the row describes has to
    // start where the file name starts. A ListTile indents its title past
    // the leading icon while leaving anything below the tile at the content
    // edge, which is how the bar came to begin 56px to the left of the file
    // name it measures.
    return SizedBox(
      width: kMediumDialogWidth,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: ArDriveSpacing.xxs / 2),
            child: icon,
          ),
          const SizedBox(width: ArDriveSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: ArDriveTypographyNew.of(context).paragraphLarge(
                    color: colorTokens.textHigh,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
                ...details,
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: ArDriveSpacing.md),
            trailing,
          ],
        ],
      ),
    );
  }

  /// The file is saved and its integrity check has not answered yet.
  ///
  /// Nothing to cancel and nothing to decide, so there are no actions: the
  /// save is already done, and this state replaces itself the moment the
  /// verdict lands (or, at the outside, when the cubit's timeout gives up on
  /// it).
  ArDriveStandardModalNew _downloadVerifyingDialog(
      BuildContext context, FileDownloadVerifying state) {
    return _modalWrapper(
      title: appLocalizationsOf(context).downloadVerifying,
      child: _fileRow(
        context,
        icon: ArDriveIcons.fileOutlined(size: 24),
        name: state.fileName,
        details: [
          Text(
            appLocalizationsOf(context).downloadVerifyingDescription,
            style: ArDriveTypographyNew.of(context).paragraphNormal(
              color: ArDriveTheme.of(context).themeData.colorTokens.textMid,
            ),
          ),
        ],
        trailing: const ArDriveSpinner(),
      ),
    );
  }

  ArDriveStandardModalNew downloadFinishedWithSuccessDialog(
      BuildContext context, FileDownloadFinishedWithSuccess state) {
    // A verdict of `failed` is not a footnote on a success. The bytes are on
    // disk and they contradict what was signed, so the dialog leads with that
    // instead of congratulating the user underneath it.
    if (state.integrity == DataItemIntegrityVerdict.failed) {
      return _integrityFailureDialog(
        context,
        title: appLocalizationsOf(context).downloadVerificationFailed,
        description: appLocalizationsOf(context)
            .downloadVerificationFailedDescription(state.fileName),
        onDismiss: () {
          context.read<FileDownloadCubit>().abortDownload();
          Navigator.pop(context);
        },
      );
    }

    // Nothing is said about a check that passed.
    //
    // "Verified" claimed more than it did. It never meant the bytes were
    // checked against what the uploader signed - that is the data item
    // signature, and it is not fetched here. It meant the AES-GCM MAC checked
    // out, which is a real cryptographic check but not one the user can ever
    // learn anything from: a MAC that fails throws out of the download, so the
    // dialog below is only ever reached when it passed. A label on 100% of
    // successes carries no information.
    //
    // It was also asymmetric. Only private GCM files could earn it, so a badge
    // on those and silence on everything else implied public downloads were
    // the lesser thing, which is the opposite of true and not a claim worth
    // making by accident.
    return _modalWrapper(
      title: appLocalizationsOf(context).downloadFinished,
      description: state.fileName,
      actions: [
        ModalAction.close(
          action: () {
            context.read<FileDownloadCubit>().abortDownload();
            Navigator.pop(context);
          },
          title: appLocalizationsOf(context).doneEmphasized,
        ),
      ],
    );
  }

  ArDriveStandardModalNew _downloadingFileWithProgressDialog(
      BuildContext context, FileDownloadWithProgress state) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final progressText =
        '${filesize(((state.fileSize) * (state.progress / 100)).ceil())}/${filesize(state.fileSize)}';

    // The bar keeps its position while the transport reconnects, because the
    // position is true: a resume picks up from the last byte that arrived, and
    // an indeterminate sweep would throw away real information to imply a
    // restart that is not happening - the download that genuinely does start
    // over has its own dialog, see
    // [FileDownloadFailureReason.downloadMustRestart]. What the bar does give
    // up is its colour, so the stall shows in the bar itself and not only in
    // the word above it, without anything moving to suggest bytes are still
    // arriving.
    //
    // The bar is the design system's, so it fills in the primary red like
    // every other progress bar. Stalled, it turns `textHigh`: the change that
    // reads against the red as well as against the track (4.1:1 and 9.9:1
    // dark, 2.1:1 and 5.9:1 light, on top of the change of hue), which is
    // what keeps 62% legible as a position. The grey tokens that look
    // "inactive" all sit within 1.6:1 of the red.
    final Color? indicatorColor;
    if (state.isReconnecting) {
      indicatorColor = colorTokens.textHigh;
    } else if (state.progress == 100) {
      indicatorColor = colorTokens.statusSuccessFg;
    } else {
      indicatorColor = null;
    }

    return _modalWrapper(
      title: appLocalizationsOf(context).downloadingFile,
      child: _fileRow(
        context,
        icon: getIconForContentType(state.contentType, size: 24),
        name: state.fileName,
        details: [
          AnimatedSwitcher(
            duration: const Duration(seconds: 1),
            // A dropped connection stops the bar without stopping the
            // download. The key is what makes the switcher treat this
            // as a new child and cross-fade it, rather than silently
            // editing the string.
            child: Text(
              state.isReconnecting
                  ? appLocalizationsOf(context).downloadReconnecting
                  : appLocalizationsOf(context).downloading,
              key: ValueKey<bool>(state.isReconnecting),
              style: typography.paragraphNormal(
                color: state.isReconnecting
                    ? colorTokens.textHigh
                    : colorTokens.textMid,
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
          ),
          Text(
            progressText,
            style: typography.paragraphNormal(color: colorTokens.textLow),
          ),
          const SizedBox(height: ArDriveSpacing.sm),
          Row(
            children: [
              Expanded(
                child: ArDriveLinearProgress(
                  value: state.progress / 100,
                  color: indicatorColor,
                ),
              ),
              const SizedBox(width: ArDriveSpacing.sm),
              // Fixed width so the bar's right-hand end does not
              // twitch left and right as the reading goes 9% to 62%
              // to 100%.
              SizedBox(
                width: 40,
                child: Text(
                  '${state.progress}%',
                  textAlign: TextAlign.right,
                  style: typography
                      .paragraphNormal(
                    color: colorTokens.textHigh,
                    fontWeight: ArFontWeight.semiBold,
                  )
                      .copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        ModalAction.dismiss(
          action: () {
            context.read<FileDownloadCubit>().abortDownload();
            Navigator.pop(context);
          },
          title: appLocalizationsOf(context).cancel,
        ),
      ],
    );
  }

  /// The two ways the integrity check can say "these are not the bytes that
  /// were signed": an error notice, the one treatment in this app for copy
  /// that has to be read rather than clicked past.
  ArDriveStandardModalNew _integrityFailureDialog(
    BuildContext context, {
    required String title,
    required String description,
    required VoidCallback onDismiss,
  }) {
    return ArDriveStandardModalNew(
      title: title,
      content: SizedBox(
        width: kMediumDialogWidth,
        child: ArDriveNotice(
          type: ArDriveNoticeType.error,
          message: description,
        ),
      ),
      actions: [
        ModalAction.close(
          action: onDismiss,
          title: appLocalizationsOf(context).close,
        ),
      ],
    );
  }

  ArDriveStandardModalNew _modalWrapper({
    Widget? child,
    String? description,
    required String title,
    List<ModalAction>? actions,
  }) {
    return ArDriveStandardModalNew(
      title: title,
      content: child,
      actions: actions,
      description: description,
    );
  }

  ArDriveStandardModalNew _fileDownloadAbortedDialog(BuildContext context) {
    return _modalWrapper(
      title: appLocalizationsOf(context).downloadCancelled,
      description: appLocalizationsOf(context).downloadCancelledDescription,
      actions: [
        ModalAction.close(
          action: () => Navigator.pop(context),
          title: appLocalizationsOf(context).close,
        ),
      ],
    );
  }
}

/// The body of the finished-download modal: what was saved, and what the
/// integrity check made of it.
///
/// The advisory is deliberately quiet. A [DataItemIntegrityVerdict.verified]
/// file gets one affirmative line, and a
/// [DataItemIntegrityVerdict.notVerified] one gets a line saying so *without*
/// suggesting anything is wrong - because usually nothing is. A resumed
/// download and a file signed with an Ethereum or Solana wallet both land
/// there, and both are perfectly good files.
///
/// [DataItemIntegrityVerdict.failed] never reaches here; it takes over the
/// whole modal instead. See
/// [FileDownloadDialog.downloadFinishedWithSuccessDialog].
