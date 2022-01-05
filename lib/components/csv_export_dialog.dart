import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pedantic/pedantic.dart';

import 'components.dart';

Future<void> promptToExportCSVData({
  required BuildContext context,
  required String driveId,
}) =>
    showDialog(
      context: context,
      builder: (_) => BlocProvider<DataExportCubit>(
        create: (_) {
          return DataExportCubit(
            driveId: driveId,
            driveDao: context.read<DriveDao>(),
            gatewayURL:
                context.read<ArweaveService>().client.api.gatewayUrl.toString(),
          )..exportData();
        },
        child: FileDownloadDialog(),
      ),
    );

class FileDownloadDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      BlocConsumer<DataExportCubit, DataExportState>(
        listener: (context, state) async {
          if (state is DataExportSuccess) {
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
              title: 'Downloading CSV...',
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Center(child: CircularProgressIndicator()),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel'),
                ),
              ],
            );
          } else if (state is FileDownloadInProgress) {
            return AppDialog(
              dismissable: false,
              title: 'Downloading CSV...',
              content: SizedBox(
                width: kMediumDialogWidth,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Exporting your data, please wait.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const CircularProgressIndicator(),
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    context.read<FileDownloadCubit>().abortDownload();
                    Navigator.pop(context);
                  },
                  child: Text('Cancel'),
                ),
              ],
            );
          } else if (state is FileDownloadFailure) {
            return AppDialog(
              dismissable: false,
              title: 'File download failed',
              content: SizedBox(
                width: kMediumDialogWidth,
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('OK'),
                ),
              ],
            );
          } else {
            return const SizedBox();
          }
        },
      );
}
