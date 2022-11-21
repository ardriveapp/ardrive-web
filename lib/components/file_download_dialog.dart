import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/progress_bar.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/arfs/repository/arfs_repository.dart';
import 'package:ardrive/core/decrypt.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/main.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components.dart';

Future<void> promptToDownloadProfileFile({
  required BuildContext context,
  required FileWithLatestRevisionTransactions file,
}) async {
  final ARFSFileEntity arfsFile =
      ARFSFactory().getARFSFileFromFileWithLatestRevisionTransactions(file);

  final profileState = context.read<ProfileCubit>().state;
  final cipherKey =
      profileState is ProfileLoggedIn ? profileState.cipherKey : null;
  final cubit = ProfileFileDownloadCubit(
    arfsRepository: ARFSRepository(
      context.read<DriveDao>(),
      ARFSFactory(),
    ),
    decrypt: Decrypt(),
    downloadService: DownloadService(arweave),
    downloader: ArDriveDownloader(),
    file: arfsFile,
    driveDao: context.read<DriveDao>(),
    arweave: context.read<ArweaveService>(),
  )..download(cipherKey);

  return showDialog(
    context: context,
    builder: (_) => BlocProvider<FileDownloadCubit>.value(
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
  final cipherKey =
      profileState is ProfileLoggedIn ? profileState.cipherKey : null;
  final cubit = ProfileFileDownloadCubit(
    arfsRepository: ARFSRepository(
      context.read<DriveDao>(),
      ARFSFactory(),
    ),
    decrypt: Decrypt(),
    downloadService: DownloadService(arweave),
    downloader: ArDriveDownloader(),
    file: arfsFile,
    driveDao: context.read<DriveDao>(),
    arweave: context.read<ArweaveService>(),
  )..download(cipherKey);

  return showDialog(
    context: context,
    builder: (_) => BlocProvider<FileDownloadCubit>.value(
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

  Widget _fileDownloadFailedDialog(BuildContext context) {
    return AppDialog(
      dismissable: false,
      title: appLocalizationsOf(context).fileFailedToDownload,
      content: SizedBox(
        width: kMediumDialogWidth,
        child: Text(appLocalizationsOf(context).tryAgainDownloadingFile),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(appLocalizationsOf(context).ok),
        ),
      ],
    );
  }

  Widget _fileDownloadFailedDueToFileAbovePrivateLimit(BuildContext context) {
    return AppDialog(
      dismissable: false,
      title: appLocalizationsOf(context).warningEmphasized,
      content: SizedBox(
        width: kMediumDialogWidth,
        child: Text(
            appLocalizationsOf(context).fileFailedToDownloadFileAboveLimit),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(appLocalizationsOf(context).ok),
        ),
      ],
    );
  }

  Widget _warningToWaitDownloadFinishes(BuildContext context) {
    return AppDialog(
      dismissable: false,
      title: appLocalizationsOf(context).warningEmphasized,
      content: SizedBox(
        width: kMediumDialogWidth,
        child: Text(appLocalizationsOf(context).waitForDownload),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(appLocalizationsOf(context).cancel),
        ),
        ElevatedButton(
          onPressed: () {
            final profileState = context.read<ProfileCubit>().state;

            final cipherKey =
                profileState is ProfileLoggedIn ? profileState.cipherKey : null;

            (context.read<FileDownloadCubit>() as ProfileFileDownloadCubit)
                .download(cipherKey);
          },
          child: Text(appLocalizationsOf(context).ok),
        ),
      ],
    );
  }

  Widget _downloadStartingDialog(BuildContext context) {
    return AppDialog(
      dismissable: false,
      title: appLocalizationsOf(context).downloadingFile,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Center(child: CircularProgressIndicator()),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(appLocalizationsOf(context).cancel),
        ),
      ],
    );
  }

  Widget _fileDownloadInProgressDialog(
      BuildContext context, FileDownloadInProgress state) {
    return AppDialog(
      dismissable: false,
      title: appLocalizationsOf(context).downloadingFile,
      content: SizedBox(
        width: kMediumDialogWidth,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            state.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(filesize(state.totalByteCount)),
          trailing: const CircularProgressIndicator(),
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () async {
            await context.read<FileDownloadCubit>().abortDownload();
            // ignore: use_build_context_synchronously
            Navigator.pop(context);
          },
          child: Text(appLocalizationsOf(context).cancel),
        ),
      ],
    );
  }

  Widget downloadFinishedWithSuccessDialog(
      BuildContext context, FileDownloadFinishedWithSuccess state) {
    return AppDialog(
      dismissable: false,
      title: appLocalizationsOf(context).downloadFinished,
      content: SizedBox(
        width: kMediumDialogWidth,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            state.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () {
            context.read<FileDownloadCubit>().abortDownload();
            Navigator.pop(context);
          },
          child: Text(appLocalizationsOf(context).doneEmphasized),
        ),
      ],
    );
  }

  Widget _downloadingFileWithProgressDialog(
      BuildContext context, FileDownloadWithProgress state) {
    return AppDialog(
      dismissable: false,
      title: appLocalizationsOf(context).downloadingFile,
      content: SizedBox(
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
                  filesize((state.fileSize * (state.progress / 100)).round()) +
                      ' / ' +
                      filesize(state.fileSize)),
            ),
            ProgressBar(
                percentage: (context.read<FileDownloadCubit>()
                        as ProfileFileDownloadCubit)
                    .downloadProgress)
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () {
            context.read<FileDownloadCubit>().abortDownload();
            Navigator.pop(context);
          },
          child: Text(appLocalizationsOf(context).cancel),
        ),
      ],
    );
  }
}
