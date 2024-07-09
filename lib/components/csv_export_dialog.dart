import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/data_export/data_export_cubit.dart';
import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> promptToExportCSVData({
  required BuildContext context,
  required String driveId,
}) =>
    showArDriveDialog(
      context,
      content: BlocProvider<DataExportCubit>(
        create: (_) {
          return DataExportCubit(
            driveId: driveId,
            driveDao: context.read<DriveDao>(),
            folderRepository: context.read<FolderRepository>(),
            gatewayURL:
                context.read<ArweaveService>().client.api.gatewayUrl.toString(),
          )..exportData();
        },
        child: const FileDownloadDialog(),
      ),
      barrierDismissible: false,
    );

class FileDownloadDialog extends StatelessWidget {
  const FileDownloadDialog({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<DataExportCubit, DataExportState>(
        listener: (context, state) async {
          if (state is DataExportSuccess) {
            final ArDriveIO io = ArDriveIO();

            final saveFile = io.saveFile(await IOFile.fromData(state.bytes,
                name: state.fileName, lastModifiedDate: state.lastModified));

            saveFile.then((value) => Navigator.pop(context));
          }
        },
        builder: (context, state) {
          if (state is FileDownloadStarting) {
            return ArDriveStandardModal(
              title: appLocalizationsOf(context).downloadingCSV,
              content: const Column(
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
          } else if (state is FileDownloadInProgress) {
            return ArDriveStandardModal(
              title: appLocalizationsOf(context).downloadingCSV,
              content: SizedBox(
                width: kMediumDialogWidth,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    appLocalizationsOf(context).exportingData,
                  ),
                  trailing: const CircularProgressIndicator(),
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
          } else if (state is FileDownloadFailure) {
            return ArDriveStandardModal(
              title: appLocalizationsOf(context).fileDownloadFailed,
              content: const SizedBox(
                width: kMediumDialogWidth,
              ),
              actions: [
                ModalAction(
                  action: () => Navigator.pop(context),
                  title: appLocalizationsOf(context).ok,
                ),
              ],
            );
          } else {
            return const SizedBox();
          }
        },
      );
}
