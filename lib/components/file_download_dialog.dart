import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/progress_bar.dart';
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
}) =>
    showDialog(
      context: context,
      builder: (_) => BlocProvider<FileDownloadCubit>(
        create: (_) => ProfileFileDownloadCubit(
          driveId: file.driveId,
          fileId: file.id,
          revisionDataTxId: file.dataTxId,
          dataContentType: file.dataContentType,
          fileName: file.name,
          fileSize: file.size,
          lastModified: file.lastModifiedDate,
          profileCubit: context.read<ProfileCubit>(),
          driveDao: context.read<DriveDao>(),
          arweave: context.read<ArweaveService>(),
        ),
        child: const FileDownloadDialog(),
      ),
    );

Future<void> promptToDownloadFileRevision({
  required BuildContext context,
  required FileRevisionWithTransactions revision,
}) =>
    showDialog(
      context: context,
      builder: (_) => BlocProvider<FileDownloadCubit>(
        create: (_) => ProfileFileDownloadCubit(
          driveId: revision.driveId,
          fileId: revision.fileId,
          revisionDataTxId: revision.dataTxId,
          dataContentType: revision.dataContentType,
          fileName: revision.name,
          fileSize: revision.size,
          lastModified: revision.lastModifiedDate,
          profileCubit: context.read<ProfileCubit>(),
          driveDao: context.read<DriveDao>(),
          arweave: context.read<ArweaveService>(),
        ),
        child: const FileDownloadDialog(),
      ),
    );

Future<void> promptToDownloadSharedFile({
  required BuildContext context,
  SecretKey? fileKey,
  required FileRevision revision,
}) =>
    showDialog(
      context: context,
      builder: (_) => BlocProvider<FileDownloadCubit>(
        create: (_) => SharedFileDownloadCubit(
          revision: revision,
          fileKey: fileKey,
          arweave: context.read<ArweaveService>(),
        ),
        child: const FileDownloadDialog(),
      ),
    );

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
            return _fileDownloadFailedDialog(context);
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
