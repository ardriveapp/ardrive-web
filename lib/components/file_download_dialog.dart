import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:cryptography/cryptography.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pedantic/pedantic.dart';

import 'components.dart';

Future<void> promptToDownloadProfileFile({
  required BuildContext context,
  required DriveID driveId,
  required FileID fileId,
  required TxID dataTxId,
}) =>
    showDialog(
      context: context,
      builder: (_) => BlocProvider<FileDownloadCubit>(
        create: (_) => ProfileFileDownloadCubit(
          driveId: driveId,
          fileId: fileId,
          dataTxId: dataTxId,
          profileCubit: context.read<ProfileCubit>(),
          driveDao: context.read<DriveDao>(),
          arweave: context.read<ArweaveService>(),
        ),
        child: FileDownloadDialog(),
      ),
    );

Future<void> promptToDownloadSharedFile({
  required BuildContext context,
  required String fileId,
  SecretKey? fileKey,
}) =>
    showDialog(
      context: context,
      builder: (_) => BlocProvider<FileDownloadCubit>(
        create: (_) => SharedFileDownloadCubit(
          fileId: fileId,
          fileKey: fileKey,
          arweave: context.read<ArweaveService>(),
        ),
        child: FileDownloadDialog(),
      ),
    );

class FileDownloadDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      BlocConsumer<FileDownloadCubit, FileDownloadState>(
        listener: (context, state) async {
          if (state is FileDownloadSuccess) {
            final savePath = await getSavePath();
            if (savePath != null) {
              unawaited(state.file.saveTo(savePath));
            }

            Navigator.pop(context);
          }
        },
        builder: (context, state) {
          if (state is FileDownloadStarting) {
            return AppDialog(
              dismissable: false,
              title: appLocalizationsOf(context).downloadingFile,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Center(child: CircularProgressIndicator()),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(appLocalizationsOf(context).cancel),
                ),
              ],
            );
          } else if (state is FileDownloadInProgress) {
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
                  onPressed: () {
                    context.read<FileDownloadCubit>().abortDownload();
                    Navigator.pop(context);
                  },
                  child: Text(appLocalizationsOf(context).cancel),
                ),
              ],
            );
          } else if (state is FileDownloadFailure) {
            return AppDialog(
              dismissable: false,
              title: appLocalizationsOf(context).fileFailedToDownload,
              content: SizedBox(
                width: kMediumDialogWidth,
                child:
                    Text(appLocalizationsOf(context).tryAgainDownloadingFile),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(appLocalizationsOf(context).ok),
                ),
              ],
            );
          } else {
            return const SizedBox();
          }
        },
      );
}
