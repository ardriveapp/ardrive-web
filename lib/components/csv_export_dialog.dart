import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/data_export/data_export_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
        child: const FileDownloadDialog(),
      ),
    );

class FileDownloadDialog extends StatelessWidget {
  const FileDownloadDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<DataExportCubit, DataExportState>(
        listener: (context, state) async {
          if (state is DataExportSuccess) {
            final ArDriveIO io = ArDriveIO();

            await io.saveFile(await IOFile.fromData(state.bytes,
                name: state.fileName, lastModifiedDate: state.lastModified));

            Navigator.pop(context);
          }
        },
        builder: (context, state) {
          if (state is FileDownloadStarting) {
            return AppDialog(
              dismissable: false,
              title: appLocalizationsOf(context).downloadingCSV,
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
          } else if (state is FileDownloadInProgress) {
            return AppDialog(
              dismissable: false,
              title: appLocalizationsOf(context).downloadingCSV,
              content: SizedBox(
                width: kMediumDialogWidth,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    appLocalizationsOf(context).exportingData,
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
                  child: Text(appLocalizationsOf(context).cancel),
                ),
              ],
            );
          } else if (state is FileDownloadFailure) {
            return AppDialog(
              dismissable: false,
              title: appLocalizationsOf(context).fileDownloadFailed,
              content: SizedBox(
                width: kMediumDialogWidth,
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
