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
                    ModalAction(
                      action: () => Navigator.pop(context),
                      title: appLocalizationsOf(context).ok,
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
              case FileDownloadFailureReason.fileAboveLimit:
                return _fileDownloadFailedDueToFileAbovePrivateLimit(context);
              case FileDownloadFailureReason.browserDoesNotSupportLargeDownloads:
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
        ModalAction(
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
      title: appLocalizationsOf(context).warningEmphasized,
      description:
          appLocalizationsOf(context).fileFailedToDownloadFileAboveLimit,
      actions: [
        ModalAction(
          action: () => Navigator.pop(context),
          title: appLocalizationsOf(context).ok,
        ),
      ],
    );
  }

  ArDriveStandardModalNew _fileDownloadFailedDueToAboveBrowserLimit(
      BuildContext context) {
    return _modalWrapper(
      title: appLocalizationsOf(context).warningEmphasized,
      description:
          appLocalizationsOf(context).fileFailedToDownloadFileAbovePublicLimit,
      actions: [
        ModalAction(
          action: () => Navigator.pop(context),
          title: appLocalizationsOf(context).ok,
        ),
      ],
    );
  }

  ArDriveStandardModalNew _warningToWaitDownloadFinishes(BuildContext context) {
    return _modalWrapper(
        title: appLocalizationsOf(context).warningEmphasized,
        description: appLocalizationsOf(context).waitForDownload,
        actions: [
          ModalAction(
            action: () {
              final profileState = context.read<ProfileCubit>().state;

              final cipherKey = profileState is ProfileLoggedIn
                  ? profileState.user.cipherKey
                  : null;

              (context.read<FileDownloadCubit>() as ProfileFileDownloadCubit)
                  .download(cipherKey);
            },
            title: appLocalizationsOf(context).ok,
          ),
          ModalAction(
            action: () => Navigator.pop(context),
            title: appLocalizationsOf(context).cancel,
          ),
        ]);
  }

  ArDriveStandardModalNew _downloadStartingDialog(BuildContext context) {
    return _modalWrapper(
      title: appLocalizationsOf(context).downloadingFile,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(child: CircularProgressIndicator()),
        ],
      ),
      actions: [
        ModalAction(
          action: () => Navigator.pop(context),
          title: appLocalizationsOf(context).cancel,
        ),
      ],
    );
  }

  ArDriveStandardModalNew _fileDownloadInProgressDialog(
      BuildContext context, FileDownloadInProgress state) {
    return _modalWrapper(
      title: appLocalizationsOf(context).downloadingFile,
      child: SizedBox(
        width: kMediumDialogWidth,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            state.fileName,
            style: ArDriveTypography.body.bodyRegular(
              color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            ),
          ),
          subtitle: Text(
            filesize(
              state.totalByteCount,
            ),
            style: ArDriveTypography.body.smallRegular(
              color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            ),
          ),
          trailing: const CircularProgressIndicator(),
        ),
      ),
      actions: [
        ModalAction(
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
      child: SizedBox(
        width: kMediumDialogWidth,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            state.fileName,
            style: ArDriveTypography.body.bodyRegular(
              color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            ),
          ),
          subtitle: Text(
            appLocalizationsOf(context).downloadVerifyingDescription,
            style: ArDriveTypography.body.smallRegular(
              color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            ),
          ),
          trailing: const CircularProgressIndicator(),
        ),
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
        ModalAction(
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
    final theme = ArDriveTheme.of(context).themeData;
    final colors = theme.colors;
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
    // `textLow` and not `themeFgOnDisabled`, which would be the obvious
    // "inactive" token: in the dark theme that is grey.300 against a white
    // fill, a change of 1.3:1 that nobody can see on a 4px bar. `textLow`
    // reads as a change against the fill in both themes (3.7:1 light, 4.1:1
    // dark) while staying visible against the track (5.0:1 and 4.5:1), which
    // is what keeps 62% legible as a position.
    final Color indicatorColor;
    if (state.isReconnecting) {
      indicatorColor = theme.colorTokens.textLow;
    } else if (state.progress == 100) {
      indicatorColor = colors.themeSuccessDefault;
    } else {
      indicatorColor = colors.themeFgDefault;
    }

    return _modalWrapper(
      title: appLocalizationsOf(context).downloadingFile,
      // A [Row] rather than a [ListTile]: everything the bar describes - the
      // file name, the status and the byte count - has to start where the bar
      // starts. A ListTile indents its title past the leading icon while
      // leaving anything below the tile at the content edge, which is how the
      // bar came to begin 56px to the left of the file name it measures.
      child: SizedBox(
        width: kLargeDialogWidth,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: getIconForContentType(
                state.contentType,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.fileName,
                    style: ArDriveTypography.body.bodyBold(
                      color: colors.themeFgDefault,
                    ),
                  ),
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
                      style: ArDriveTypography.body.buttonNormalBold(
                        color: state.isReconnecting
                            ? colors.themeFgDefault
                            : colors.themeFgOnDisabled,
                      ),
                    ),
                  ),
                  Text(
                    progressText,
                    style: ArDriveTypography.body.buttonNormalRegular(
                      color: colors.themeFgOnDisabled,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ArDriveProgressBar(
                          height: 4,
                          indicatorColor: indicatorColor,
                          percentage: state.progress / 100,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Fixed width so the bar's right-hand end does not
                      // twitch left and right as the reading goes 9% to 62%
                      // to 100%.
                      SizedBox(
                        width: 40,
                        child: Text(
                          '${state.progress}%',
                          textAlign: TextAlign.right,
                          style: ArDriveTypography.body.buttonNormalBold(
                            color: colors.themeFgDefault,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        ModalAction(
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
  /// were signed", given the one treatment in this app reserved for copy that
  /// has to be read rather than clicked past.
  ///
  /// Built by hand instead of through [_modalWrapper] because the difference
  /// *is* the shape. Every [ArDriveModalNew] wears the same red strip, so red
  /// on its own separates nothing here - "Download finished!" has one too.
  /// What separates this modal is an alert icon beside the title and a body
  /// lifted out of running text into the bordered notice panel that the share
  /// dialog's pending-file warning and the seed-phrase modal already use for
  /// the sentences they need read.
  ArDriveStandardModalNew _integrityFailureDialog(
    BuildContext context, {
    required String title,
    required String description,
    required VoidCallback onDismiss,
  }) {
    // `colorTokens.textRed` rather than anything from the older `colors`: it is
    // the one red that clears 3:1 on the modal surface *and* on the notice
    // panel in *both* themes (3.7/3.6 and 4.2/3.9). `themeErrorDefault` is the
    // same red.400 either way and manages only 2.5:1 on the light surface,
    // which is a warning sign nobody with low vision would find.
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return ArDriveStandardModalNew(
      titleWidget: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            // The sentence says everything the icon does; announcing it twice
            // is noise.
            child: ExcludeSemantics(
              child: ArDriveIcons.triangle(
                size: 24,
                color: colorTokens.textRed,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              title,
              style: typography.heading3(fontWeight: ArFontWeight.bold),
            ),
          ),
        ],
      ),
      content: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorTokens.containerL1,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorTokens.textRed),
        ),
        child: Text(
          description,
          // `textHigh`, not the red: ~9.4:1 light and ~14.7:1 dark on this
          // panel, where the red would be ~4:1 and short of AA for body copy.
          // The border and the icon carry the severity; the sentence only has
          // to be readable.
          style: typography.paragraphSmall(color: colorTokens.textHigh),
        ),
      ),
      actions: [
        ModalAction(
          action: onDismiss,
          title: appLocalizationsOf(context).ok,
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
        ModalAction(
          action: () => Navigator.pop(context),
          title: appLocalizationsOf(context).ok,
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
