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
                return _modalWrapper(
                  title: appLocalizationsOf(context).downloadIntegrityFailed,
                  description: appLocalizationsOf(context)
                      .downloadIntegrityFailedDescription,
                  actions: [
                    ModalAction(
                      action: () => Navigator.pop(context),
                      title: appLocalizationsOf(context).ok,
                    ),
                  ],
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
      return _modalWrapper(
        title: appLocalizationsOf(context).downloadVerificationFailed,
        description: appLocalizationsOf(context)
            .downloadVerificationFailedDescription(state.fileName),
        actions: [
          ModalAction(
            action: () {
              context.read<FileDownloadCubit>().abortDownload();
              Navigator.pop(context);
            },
            title: appLocalizationsOf(context).ok,
          ),
        ],
      );
    }

    return _modalWrapper(
      title: appLocalizationsOf(context).downloadFinished,
      // The file name would normally be the modal's `description`, but
      // [ArDriveStandardModalNew] renders `description` only when there is no
      // `content`, so the advisory has to bring the name with it.
      child: _DownloadOutcome(
        fileName: state.fileName,
        integrity: state.integrity,
      ),
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
    final progressText =
        '${filesize(((state.fileSize) * (state.progress / 100)).ceil())}/${filesize(state.fileSize)}';
    return _modalWrapper(
        title: appLocalizationsOf(context).downloadingFile,
        child: SizedBox(
          width: kLargeDialogWidth,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: getIconForContentType(
                state.contentType,
                size: 24,
              ),
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.fileName,
                          style: ArDriveTypography.body.bodyBold(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgDefault,
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(seconds: 1),
                          // A dropped connection stops the bar without
                          // stopping the download. The key is what makes the
                          // switcher treat this as a new child and cross-fade
                          // it, rather than silently editing the string.
                          child: Text(
                            state.isReconnecting
                                ? appLocalizationsOf(context)
                                    .downloadReconnecting
                                : appLocalizationsOf(context).downloading,
                            key: ValueKey<bool>(state.isReconnecting),
                            style: ArDriveTypography.body.buttonNormalBold(
                              color: state.isReconnecting
                                  ? ArDriveTheme.of(context)
                                      .themeData
                                      .colors
                                      .themeFgDefault
                                  : ArDriveTheme.of(context)
                                      .themeData
                                      .colors
                                      .themeFgOnDisabled,
                            ),
                          ),
                        ),
                        Text(
                          progressText,
                          style: ArDriveTypography.body.buttonNormalRegular(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgOnDisabled,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: [
                Expanded(
                  flex: 2,
                  child: ArDriveProgressBar(
                    height: 4,
                    indicatorColor: state.progress == 100
                        ? ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeSuccessDefault
                        : ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault,
                    percentage: state.progress / 100,
                  ),
                ),
                Text(
                  '${(state.progress).toInt()}%',
                  style: ArDriveTypography.body.buttonNormalBold(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgDefault,
                  ),
                ),
              ],
            ),
          ]),
        ),
        actions: [
          ModalAction(
            action: () {
              context.read<FileDownloadCubit>().abortDownload();
              Navigator.pop(context);
            },
            title: appLocalizationsOf(context).cancel,
          ),
        ]);
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
class _DownloadOutcome extends StatelessWidget {
  const _DownloadOutcome({
    required this.fileName,
    required this.integrity,
  });

  final String fileName;

  /// `null` when no check was run at all, in which case nothing is said about
  /// one.
  final DataItemIntegrityVerdict? integrity;

  @override
  Widget build(BuildContext context) {
    final verdict = integrity;

    return SizedBox(
      width: kMediumDialogWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            fileName,
            // The style [ArDriveStandardModalNew] gives its own `description`,
            // which is where this line sits on every other download dialog.
            style: ArDriveTypography.body.smallRegular(),
            textAlign: TextAlign.left,
          ),
          if (verdict != null) ...[
            const SizedBox(height: 12),
            _IntegrityNotice(verdict: verdict),
          ],
        ],
      ),
    );
  }
}

/// One line about the integrity check, in the icon-plus-caption shape the rest
/// of the app uses for advisory notices.
class _IntegrityNotice extends StatelessWidget {
  const _IntegrityNotice({required this.verdict});

  final DataItemIntegrityVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final isLight = ArDriveTheme.of(context).themeData.name == 'light';

    final Widget icon;
    final Color color;
    final String message;

    switch (verdict) {
      case DataItemIntegrityVerdict.verified:
        // `themeSuccessDefault` is green.400 in both themes and reads at only
        // ~2.2:1 on a light surface, so the light theme takes the muted green
        // instead - the same substitution the recipient page documents in
        // [SharedFileColors.success].
        color = isLight ? colors.themeSuccessMuted : colors.themeSuccessDefault;
        icon = ArDriveIcons.checkCirle(size: 16, color: color);
        message = appLocalizationsOf(context).downloadVerified;
        break;
      case DataItemIntegrityVerdict.notVerified:
        // Neutral, never a warning triangle: no verdict is not a problem, and
        // an alarm icon would say otherwise louder than the sentence next to
        // it says the opposite.
        color = colors.themeFgMuted;
        icon = ArDriveIcons.info(size: 16, color: color);
        message = appLocalizationsOf(context).downloadNotVerified;
        break;
      case DataItemIntegrityVerdict.failed:
        // Unreachable: a failed verdict takes over the modal.
        color = colors.themeErrorDefault;
        icon = ArDriveIcons.triangle(size: 16, color: color);
        message = appLocalizationsOf(context).downloadVerificationFailed;
        break;
    }

    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: icon),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: ArDriveTypography.body.captionRegular(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
