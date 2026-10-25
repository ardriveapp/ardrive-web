import 'dart:async';

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
        child: const CsvExportDialog(),
      ),
      barrierDismissible: false,
    );

/// Exports a drive's file list as a CSV and saves it.
///
/// Built against the states [DataExportCubit] actually emits. It used to check
/// the download dialog's states, which this cubit never emits, so it drew
/// nothing at all: an invisible dialog that could not be dismissed until the
/// file was ready, a failure that was never shown, and a Cancel that reached
/// for a cubit this dialog does not have.
class CsvExportDialog extends StatelessWidget {
  const CsvExportDialog({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<DataExportCubit, DataExportState>(
        listener: (context, state) async {
          if (state is DataExportSuccess) {
            final cubit = context.read<DataExportCubit>();
            try {
              await ArDriveIO().saveFile(await IOFile.fromData(state.bytes,
                  name: state.fileName, lastModifiedDate: state.lastModified));
              if (context.mounted) Navigator.pop(context);
            } catch (_) {
              cubit.reportSaveFailure();
            }
          }
        },
        builder: (context, state) {
          final strings = appLocalizationsOf(context);

          if (state is DataExportFailure) {
            return ArDriveStandardModalNew(
              title: strings.fileDownloadFailed,
              actions: [
                ModalAction(
                  action: () => Navigator.pop(context),
                  title: strings.ok,
                ),
              ],
            );
          }

          final typography = ArDriveTypographyNew.of(context);
          final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
          return ArDriveStandardModalNew(
            title: strings.downloadingCSV,
            content: SizedBox(
              width: kMediumDialogWidth,
              child: Row(
                children: [
                  const ArDriveSpinner(),
                  const SizedBox(width: ArDriveSpacing.sm),
                  Expanded(
                    child: Text(
                      strings.exportingData,
                      style: typography.paragraphNormal(
                        color: colorTokens.textMid,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // No Cancel once the file is being saved: closing the dialog
            // would not stop the save, so the file could arrive after Cancel.
            actions: state is DataExportSuccess
                ? null
                : [
                    ModalAction.dismiss(
                      action: () {
                        context.read<DataExportCubit>().abort();
                        Navigator.pop(context);
                      },
                      title: strings.cancel,
                    ),
                  ],
          );
        },
      );
}
