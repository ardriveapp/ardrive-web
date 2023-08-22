import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/file_download/file_download_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/download/multiple_download_bloc.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/arfs/repository/arfs_repository.dart';

promptToDownloadMultipleFiles(
  BuildContext context, {
  required List<FileDataTableItem> items,
}) async {
  final arweave = context.read<ArweaveService>();

  final arfsItems = items
      .map((item) => ARFSFactory().getARFSFileFromFileDataItemTable(item))
      .toList();

  final driveDetail =
      (context.read<DriveDetailCubit>().state as DriveDetailLoadSuccess);
  final profileState = context.read<ProfileCubit>().state;
  final cipherKey =
      profileState is ProfileLoggedIn ? profileState.cipherKey : null;

  showAnimatedDialog(
    context,
    barrierDismissible: false,
    content: BlocProvider(
      create: (modalContext) => MultipleDownloadBloc(
        downloadService: DownloadService(arweave),
        arfsRepository: ARFSRepository(
          context.read<DriveDao>(),
          ARFSFactory(),
        ),
        arweave: arweave,
        crypto: ArDriveCrypto(),
        driveDao: context.read<DriveDao>(),
        cipherKey: cipherKey,
      )..add(
          StartDownload(
            arfsItems,
            folderName: driveDetail.folderInView.folder.name,
          ),
        ),
      child: const MultipleFilesDownload(),
    ),
  );
}

class MultipleFilesDownload extends StatefulWidget {
  const MultipleFilesDownload({
    super.key,
  });

  @override
  State<MultipleFilesDownload> createState() => _MultipleFilesDownloadState();
}

class _MultipleFilesDownloadState extends State<MultipleFilesDownload> {
  final _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return BlocListener<MultipleDownloadBloc, MultipleDownloadState>(
      listener: (context, state) async {
        if (state is MultipleDownloadFinishedWithSuccess) {
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
      child: BlocBuilder<MultipleDownloadBloc, MultipleDownloadState>(
        builder: (context, state) {
          late Widget content;
          List<ModalAction> actions = [];

          if (state is MultipleDownloadInProgress) {
            return ArDriveStandardModal(
              width: 408,
              // TODO: Localize text
              title:
                  'Downloading file(s)... ${state.currentFileIndex + 1} of ${state.files.length}',
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 256),
                      child: ArDriveScrollBar(
                          controller: _scrollController,
                          alwaysVisible: true,
                          child: ListView.builder(
                            padding: const EdgeInsets.only(top: 0),
                            controller: _scrollController,
                            shrinkWrap: true,
                            itemCount: state.files.length,
                            itemBuilder: (BuildContext context, int index) {
                              final file = state.files[index];
                              return Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      '${file.name} ',
                                      style: ArDriveTypography.body.smallBold(
                                        color: ArDriveTheme.of(context)
                                            .themeData
                                            .colors
                                            .themeFgSubtle,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    filesize(file.size),
                                    style: ArDriveTypography.body.smallRegular(
                                      color: ArDriveTheme.of(context)
                                          .themeData
                                          .colors
                                          .themeFgMuted,
                                    ),
                                  ),
                                ],
                              );
                            },
                          )),
                    ),
                  )
                ],
              ),
              actions: [
                ModalAction(
                  action: () {
                    context
                        .read<MultipleDownloadBloc>()
                        .add(const CancelDownload());
                    Navigator.of(context).pop(false);
                  },
                  title: appLocalizationsOf(context).cancelEmphasized,
                ),
              ],
            );
          } else if (state is MultipleDownloadFailure) {
            switch (state.reason) {
              case FileDownloadFailureReason.fileAboveLimit:
                content = Text(
                  appLocalizationsOf(context)
                      .fileFailedToDownloadFileAbovePublicLimit,
                );
                break;
              case FileDownloadFailureReason.fileNotFound:
                content =
                    Text(appLocalizationsOf(context).tryAgainDownloadingFile);
                break;
              case FileDownloadFailureReason.networkConnectionError:
                content = const Text(
                    'An error occurred while downloading your file(s). Please try again.');
                break;
              default:
                content = Text(appLocalizationsOf(context).fileDownloadFailed);
            }

            actions = [
              ModalAction(
                action: () {
                  context
                      .read<MultipleDownloadBloc>()
                      .add(const CancelDownload());
                  Navigator.pop(context);
                },
                title: appLocalizationsOf(context).cancel,
              ),
              ModalAction(
                action: () {
                  context
                      .read<MultipleDownloadBloc>()
                      .add(const ResumeDownload());
                },
                title: appLocalizationsOf(context).tryAgain,
              ),
            ];
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
