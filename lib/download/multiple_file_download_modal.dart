import 'package:ardrive/blocs/file_download/file_download_cubit.dart';
import 'package:ardrive/components/progress_dialog.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/download/multiple_download_bloc.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

promptToDownloadMultipleFiles(
  BuildContext context, {
  required List<FileDataTableItem> items,
}) async {
  final arweave = context.read<ArweaveService>();

  final arfsItems = items
      .map((item) => ARFSFactory().getARFSFileFromFileDataItemTable(item))
      .toList();

  showAnimatedDialog(
    context,
    content: BlocProvider(
      create: (context) =>
          MultipleDownloadBloc(downloadService: DownloadService(arweave))
            ..add(StartDownload(arfsItems)),
      child: const MultipleFilesDonwload(),
    ),
  );
}

class MultipleFilesDonwload extends StatelessWidget {
  const MultipleFilesDonwload({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<MultipleDownloadBloc, MultipleDownloadState>(
      listener: (context, state) {
        if (state is MultipleDownloadFinishedWithSuccess) {
          Future.delayed(const Duration(seconds: 3))
              .then((value) => Navigator.pop(context));
        }
      },
      child: BlocBuilder<MultipleDownloadBloc, MultipleDownloadState>(
        builder: (context, state) {
          late Widget content;
          List<ModalAction> actions = [];

          if (state is MultipleDownloadInProgress) {
            return ProgressDialog(
              title: 'Downloading Multiple Files',
              actions: [
                ModalAction(
                  action: () {
                    Navigator.pop(context);
                  },
                  title: appLocalizationsOf(context).cancel,
                ),
              ],
            );
          } else if (state is MultipleDownloadFinishedWithSuccess) {
            content = Text(
              appLocalizationsOf(context).downloadFinished,
              style: ArDriveTypography.body.buttonLargeBold(),
            );

            actions = [
              ModalAction(
                action: () {
                  Navigator.pop(context);
                },
                title: appLocalizationsOf(context).ok,
              ),
            ];
          } else if (state is MultipleDownloadFailure) {
            if (state.reason == FileDownloadFailureReason.fileAboveLimit) {
              content = Text(
                appLocalizationsOf(context)
                    .fileFailedToDownloadFileAbovePublicLimit,
              );
            } else {
              content = Text(appLocalizationsOf(context).fileDownloadFailed);
            }
            actions = [
              ModalAction(
                action: () {
                  Navigator.pop(context);
                },
                title: appLocalizationsOf(context).ok,
              ),
            ];
          } else if (state is MultipleDownloadZippingFiles) {
            content = Text(
              appLocalizationsOf(context).zippingYourFiles,
              style: ArDriveTypography.body.buttonLargeBold(),
            );
          } else {
            content = Text(
              appLocalizationsOf(context).download,
              style: ArDriveTypography.body.buttonLargeBold(),
            );
          }

          return ArDriveStandardModal(
            title: appLocalizationsOf(context).download,
            content: content,
            actions: actions,
          );
        },
      ),
    );
  }
}
