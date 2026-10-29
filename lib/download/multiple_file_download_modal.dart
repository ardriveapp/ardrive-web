import 'package:ardrive/blocs/file_download/file_download_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/download/multiple_download_bloc.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/arfs/repository/arfs_repository.dart';
import 'download_utils.dart';

promptToDownloadMultipleFiles(
  BuildContext context, {
  required List<ArDriveDataTableItem> selectedItems,
  required String zipName,
}) async {
  final arweave = context.read<ArweaveService>();

  final driveDao = context.read<DriveDao>();

  final profileState = context.read<ProfileCubit>().state;
  final cipherKey =
      profileState is ProfileLoggedIn ? profileState.user.cipherKey : null;

  showArDriveDialog(
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
        driveDao: driveDao,
        cipherKey: cipherKey,
      )..add(
          StartDownload(
            selectedItems,
            zipName: zipName,
            confirmFirst: PublicationMode.isOn,
          ),
        ),
      child: const MultipleFilesDownload(),
    ),
  );
}

class MultipleFilesDownload extends StatefulWidget {
  const MultipleFilesDownload({
    super.key,
    this.saveFile,
  });

  /// Hands the finished zip to the browser. Tests pass their own.
  final Future<void> Function(IOFile file)? saveFile;

  @override
  State<MultipleFilesDownload> createState() => _MultipleFilesDownloadState();
}

class _MultipleFilesDownloadState extends State<MultipleFilesDownload> {
  final _scrollController = ScrollController();

  /// Whether the zip has been handed to the browser to save, so the dialog
  /// can say so before the reader closes it.
  bool _saved = false;

  /// Above this the confirmation adds that it will take a while.
  static const _largeDownload = 100 * 1024 * 1024;

  Widget _buildFileListItem(
    dynamic file,
    ArdriveTypographyNew typography,
    ArDriveColorTokens colorTokens,
  ) {
    final isFile = file is MultiDownloadFile;
    final name =
        isFile ? file.fileName : (file as MultiDownloadFolder).folderPath;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: colorTokens.containerL1,
        borderRadius: BorderRadius.circular(ArDriveRadius.control),
      ),
      child: Row(
        children: [
          Icon(
            isFile ? Icons.insert_drive_file_outlined : Icons.folder_outlined,
            size: 16,
            color: colorTokens.textLow,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: typography.paragraphSmall(
                fontWeight: ArFontWeight.semiBold,
                color: colorTokens.textHigh,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isFile)
            Text(
              filesize(file.size),
              style: typography.paragraphSmall(
                color: colorTokens.textLow,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFileList(
    List<dynamic> files,
    ArdriveTypographyNew typography,
    ArDriveColorTokens colorTokens,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 256),
      child: ArDriveScrollBar(
        controller: _scrollController,
        alwaysVisible: true,
        child: ListView.builder(
          padding: EdgeInsets.zero,
          controller: _scrollController,
          shrinkWrap: true,
          itemCount: files.length,
          itemBuilder: (context, index) =>
              _buildFileListItem(files[index], typography, colorTokens),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return BlocListener<MultipleDownloadBloc, MultipleDownloadState>(
      listener: (context, state) async {
        if (state is MultipleDownloadFinishedWithSuccess) {
          final file = await IOFile.fromData(
            state.bytes,
            name: state.fileName,
            lastModifiedDate: state.lastModified,
          );

          // It stays open on a done state rather than closing by itself,
          // which left no word that the zip was saved.
          await (widget.saveFile ?? ArDriveIO().saveFile)(file);
          if (mounted) setState(() => _saved = true);
        }
      },
      child: BlocBuilder<MultipleDownloadBloc, MultipleDownloadState>(
        builder: (context, state) {
          if (state is MultipleDownloadReady) {
            final strings = appLocalizationsOf(context);
            return ArDriveStandardModalNew(
              width: 408,
              title: strings.downloadConfirmTitle(state.fileCount),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.downloadConfirmSize(
                      filesize(state.totalSize),
                      state.fileName,
                    ),
                    style: typography.paragraphNormal(
                      color: colorTokens.textMid,
                    ),
                  ),
                  if (state.totalSize > _largeDownload) ...[
                    const SizedBox(height: 12),
                    Text(
                      strings.downloadConfirmLarge,
                      style: typography.paragraphNormal(
                        color: colorTokens.textMid,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                ModalAction(
                  action: () => Navigator.of(context).pop(false),
                  title: strings.cancelEmphasized,
                ),
                ModalAction(
                  action: () => context
                      .read<MultipleDownloadBloc>()
                      .add(const ConfirmDownload()),
                  title: strings.download,
                ),
              ],
            );
          }
          if (state is MultipleDownloadInProgress) {
            return ArDriveStandardModalNew(
              width: 408,
              title: appLocalizationsOf(context)
                  .multiDownloadDownloadingFilesProgress(
                      state.currentFileNumber, state.fileCount),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFileList(state.files, typography, colorTokens),
                ],
              ),
              actions: [
                ModalAction.dismiss(
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
          } else if (state is MultipleDownloadFinishedWithSuccess) {
            final strings = appLocalizationsOf(context);
            return ArDriveStandardModalNew(
              width: 408,
              title: strings.multiDownloadCompleteWithSkippedFiles(
                  state.skippedFiles.length),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_saved)
                    Text(
                      strings.multiDownloadSaved(state.fileName),
                      style: typography.paragraphNormal(
                        color: colorTokens.textMid,
                      ),
                    ),
                  if (_saved && state.skippedFiles.isNotEmpty)
                    const SizedBox(height: ArDriveSpacing.sm),
                  if (state.skippedFiles.isNotEmpty)
                    _buildFileList(state.skippedFiles, typography, colorTokens),
                ],
              ),
              actions: [
                ModalAction.dismiss(
                  action: () {
                    Navigator.of(context).pop(false);
                  },
                  title: strings.doneEmphasized,
                ),
              ],
            );
          } else if (state is MultipleDownloadFailure) {
            late Widget content;
            bool showRetryAndSkip = true;

            switch (state.reason) {
              case FileDownloadFailureReason.fileAboveLimit:
                content = Text(
                  appLocalizationsOf(context)
                      .fileFailedToDownloadFileAbovePublicLimit,
                  style: typography.paragraphNormal(
                    color: colorTokens.textMid,
                  ),
                );
                showRetryAndSkip = false;
                break;
              case FileDownloadFailureReason.fileNotFound:
                content = Text(
                  appLocalizationsOf(context).tryAgainDownloadingFile,
                  style: typography.paragraphNormal(
                    color: colorTokens.textMid,
                  ),
                );
                break;
              case FileDownloadFailureReason.networkConnectionError:
                content = Text(
                  appLocalizationsOf(context).multiDownloadErrorTryAgain,
                  style: typography.paragraphNormal(
                    color: colorTokens.textMid,
                  ),
                );
                break;
              default:
                content = Text(
                  appLocalizationsOf(context).fileDownloadFailed,
                  style: typography.paragraphNormal(
                    color: colorTokens.textMid,
                  ),
                );
            }

            return ArDriveStandardModalNew(
              title: appLocalizationsOf(context).download,
              content: content,
              actions: [
                ModalAction(
                  action: () {
                    context
                        .read<MultipleDownloadBloc>()
                        .add(const CancelDownload());
                    Navigator.pop(context);
                  },
                  title: appLocalizationsOf(context).cancel,
                ),
                if (showRetryAndSkip) ...[
                  ModalAction(
                    action: () {
                      context
                          .read<MultipleDownloadBloc>()
                          .add(const ResumeDownload());
                    },
                    title: appLocalizationsOf(context).tryAgain,
                  ),
                  ModalAction(
                    action: () {
                      context
                          .read<MultipleDownloadBloc>()
                          .add(const SkipFileAndResumeDownload());
                    },
                    title: appLocalizationsOf(context).skip,
                  ),
                ]
              ],
            );
          }

          return ArDriveStandardModalNew(
            title: appLocalizationsOf(context).download,
            content: Text(
              appLocalizationsOf(context).download,
              style: typography.paragraphNormal(
                color: colorTokens.textMid,
              ),
            ),
            actions: [
              ModalAction.dismiss(
                action: () => Navigator.pop(context),
                title: appLocalizationsOf(context).close,
              ),
            ],
          );
        },
      ),
    );
  }
}
