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
          } else if (state is FileDownloadFinishedWithSuccess) {
            return downloadFinishedWithSuccessDialog(context, state);
          } else if (state is FileDownloadWithProgress) {
            return _downloadingFileWithProgressDialog(context, state);
          } else if (state is FileDownloadInProgress) {
            return _fileDownloadInProgressDialog(context, state);
          } else if (state is FileDownloadFailure) {
            if (state.reason == FileDownloadFailureReason.unknownError) {
              return _fileDownloadFailedDialog(context);
            } else if (state.reason ==
                FileDownloadFailureReason.browserDoesNotSupportLargeDownloads) {
              return _fileDownloadFailedDueToAboveBrowserLimit(context);
            }

            return _fileDownloadFailedDueToFileAbovePrivateLimit(context);
          } else if (state is FileDownloadWarning) {
            return _warningToWaitDownloadFinishes(context);
          } else if (state is FileDownloadAborted) {
            return _fileDownloadAbortedDialog(context);
          } else {
            return const SizedBox();
          }
        },
      );

  ArDriveStandardModalNew _fileDownloadFailedDialog(BuildContext context) {
    return _modalWrapper(
      title: appLocalizationsOf(context).fileFailedToDownload,
      description: appLocalizationsOf(context).tryAgainDownloadingFile,
      actions: [
        ModalAction(
          action: () => Navigator.pop(context),
          title: appLocalizationsOf(context).ok,
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

  ArDriveStandardModalNew downloadFinishedWithSuccessDialog(
      BuildContext context, FileDownloadFinishedWithSuccess state) {
    return _modalWrapper(
      title: appLocalizationsOf(context).downloadFinished,
      description: appLocalizationsOf(context).downloadFinished,
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
                          child: Text(
                            'Downloading',
                            style: ArDriveTypography.body.buttonNormalBold(
                              color: ArDriveTheme.of(context)
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
    required List<ModalAction> actions,
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
      title: 'Download cancelled',
      description: 'The download was cancelled',
      actions: [
        ModalAction(
          action: () => Navigator.pop(context),
          title: appLocalizationsOf(context).ok,
        ),
      ],
    );
  }
}
