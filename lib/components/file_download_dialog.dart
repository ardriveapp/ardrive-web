import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/progress_bar.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/arfs/repository/arfs_repository.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
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
      profileState is ProfileLoggedIn ? profileState.cipherKey : null;
  final cubit = ProfileFileDownloadCubit(
    crypto: ArDriveCrypto(),
    arfsRepository: ARFSRepository(
      context.read<DriveDao>(),
      ARFSFactory(),
    ),
    downloadService: DownloadService(arweave),
    downloader: ArDriveDownloader(),
    file: arfsFile,
    driveDao: context.read<DriveDao>(),
    arweave: arweave,
  )..download(cipherKey);
  return showAnimatedDialog(
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
  required FileRevisionWithTransactions revision,
}) {
  final ARFSFileEntity arfsFile =
      ARFSFactory().getARFSFileFromFileRevisionWithTransactions(revision);
  final profileState = context.read<ProfileCubit>().state;
  final arweave = context.read<ArweaveService>();
  final cipherKey =
      profileState is ProfileLoggedIn ? profileState.cipherKey : null;
  final cubit = ProfileFileDownloadCubit(
    crypto: ArDriveCrypto(),
    arfsRepository: ARFSRepository(
      context.read<DriveDao>(),
      ARFSFactory(),
    ),
    downloadService: DownloadService(arweave),
    downloader: ArDriveDownloader(),
    file: arfsFile,
    driveDao: context.read<DriveDao>(),
    arweave: arweave,
  )..download(cipherKey);

  return showAnimatedDialog(
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
  required FileRevision revision,
}) {
  final cubit = SharedFileDownloadCubit(
    crypto: ArDriveCrypto(),
    revision: revision,
    fileKey: fileKey,
    arweave: context.read<ArweaveService>(),
  );
  return showDialog(
    context: context,
    builder: (_) => BlocProvider<FileDownloadCubit>.value(
      value: cubit,
      child: const FileDownloadDialog(),
    ),
  );
}

class FileDownloadDialog extends StatelessWidget {
  const FileDownloadDialog({Key? key}) : super(key: key);

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
            }

            return _fileDownloadFailedDueToFileAbovePrivateLimit(context);
          } else if (state is FileDownloadWarning) {
            return _warningToWaitDownloadFinishes(context);
          } else {
            return const SizedBox();
          }
        },
      );

  ArDriveStandardModal _fileDownloadFailedDialog(BuildContext context) {
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

  ArDriveStandardModal _fileDownloadFailedDueToFileAbovePrivateLimit(
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

  ArDriveStandardModal _warningToWaitDownloadFinishes(BuildContext context) {
    return _modalWrapper(
        title: appLocalizationsOf(context).warningEmphasized,
        description: appLocalizationsOf(context).waitForDownload,
        actions: [
          ModalAction(
            action: () {
              final profileState = context.read<ProfileCubit>().state;

              final cipherKey = profileState is ProfileLoggedIn
                  ? profileState.cipherKey
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

  ArDriveStandardModal _downloadStartingDialog(BuildContext context) {
    return _modalWrapper(
        title: appLocalizationsOf(context).downloadingFile,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Center(child: CircularProgressIndicator()),
          ],
        ),
        actions: [
          ModalAction(
            action: () => Navigator.pop(context),
            title: appLocalizationsOf(context).cancel,
          ),
        ]);
  }

  ArDriveStandardModal _fileDownloadInProgressDialog(
      BuildContext context, FileDownloadInProgress state) {
    return _modalWrapper(
      title: appLocalizationsOf(context).downloadingFile,
      child: SizedBox(
        width: kMediumDialogWidth,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            state.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

  ArDriveStandardModal downloadFinishedWithSuccessDialog(
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

  ArDriveStandardModal _downloadingFileWithProgressDialog(
      BuildContext context, FileDownloadWithProgress state) {
    return _modalWrapper(
        title: appLocalizationsOf(context).downloadingFile,
        child: SizedBox(
          width: kMediumDialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  state.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                    '${filesize((state.fileSize * (state.progress / 100)).round())} / ${filesize(state.fileSize)}'),
              ),
              ProgressBar(
                  percentage: (context.read<FileDownloadCubit>()
                          as ProfileFileDownloadCubit)
                      .downloadProgress)
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
        ]);
  }

  ArDriveStandardModal _modalWrapper({
    Widget? child,
    String? description,
    required String title,
    required List<ModalAction> actions,
  }) {
    return ArDriveStandardModal(
      title: title,
      content: child,
      actions: actions,
      description: description,
    );
  }
}
