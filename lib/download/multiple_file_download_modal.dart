import 'package:ardrive/blocs/file_download/file_download_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/crypto/file_keys.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/download/multiple_download_bloc.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/theme/theme.dart';
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
        fileKeys: context.read<FileKeys>(),
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

  /// Whether the save failed or was cancelled at the browser's save picker.
  /// The zip is kept in [_zip], so saving again doesn't download it again.
  bool _saveFailed = false;
  IOFile? _zip;

  Future<void> _save(IOFile file) async {
    try {
      await (widget.saveFile ?? ArDriveIO().saveFile)(file);
      if (!mounted) return;
      setState(() {
        _saved = true;
        _saveFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _saveFailed = true);
    }
  }

  /// Every state is this wide, so the dialog does not resize between them.
  static const _width = kMediumDialogWidth;

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
      padding: const EdgeInsets.symmetric(
        horizontal: ArDriveSpacing.sm,
        vertical: ArDriveSpacing.xs,
      ),
      margin: const EdgeInsets.only(bottom: ArDriveSpacing.xxs),
      decoration: BoxDecoration(
        color: colorTokens.containerL1,
        borderRadius: BorderRadius.circular(ArDriveRadius.sm),
      ),
      child: Row(
        children: [
          isFile
              ? ArDriveIcons.fileOutlined(size: 16, color: colorTokens.textLow)
              : ArDriveIcons.folderOutline(
                  size: 16,
                  color: colorTokens.textLow,
                ),
          const SizedBox(width: ArDriveSpacing.xs),
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
          _zip = file;
          await _save(file);
        }
      },
      child: BlocBuilder<MultipleDownloadBloc, MultipleDownloadState>(
        builder: (context, state) {
          if (state is MultipleDownloadReady) {
            final strings = appLocalizationsOf(context);
            return ArDriveStandardModalNew(
              width: _width,
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
                    const SizedBox(height: ArDriveSpacing.sm),
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
                ModalAction.close(
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
              width: _width,
              title: appLocalizationsOf(context)
                  .multiDownloadDownloadingFilesProgress(
                      state.currentFileNumber, state.fileCount),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ArDriveLinearProgress(
                    value: state.fileCount == 0
                        ? null
                        : (state.currentFileNumber - 1) / state.fileCount,
                  ),
                  const SizedBox(height: ArDriveSpacing.sm),
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
              width: _width,
              title: strings.multiDownloadCompleteWithSkippedFiles(
                  state.skippedFiles.length),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_saved || _saveFailed)
                    Text(
                      _saved
                          ? strings.multiDownloadSaved(state.fileName)
                          : strings.multiDownloadNotSaved(state.fileName),
                      style: typography.paragraphNormal(
                        color: colorTokens.textMid,
                      ),
                    ),
                  if ((_saved || _saveFailed) && state.skippedFiles.isNotEmpty)
                    const SizedBox(height: ArDriveSpacing.sm),
                  if (state.skippedFiles.isNotEmpty)
                    _buildFileList(state.skippedFiles, typography, colorTokens),
                ],
              ),
              actions: [
                ModalAction.close(
                  action: () {
                    Navigator.of(context).pop(false);
                  },
                  title: strings.doneEmphasized,
                ),
                if (_saveFailed && _zip != null)
                  ModalAction(
                    action: () => _save(_zip!),
                    title: strings.tryAgainEmphasized,
                  ),
              ],
            );
          } else if (state is MultipleDownloadFailure) {
            final strings = appLocalizationsOf(context);
            final String title;
            final String message;
            bool showRetryAndSkip = true;

            switch (state.reason) {
              case FileDownloadFailureReason.fileAboveLimit:
                title = strings.downloadFileTooLargeTitle;
                message = strings.fileFailedToDownloadFileAbovePublicLimit;
                showRetryAndSkip = false;
                break;
              case FileDownloadFailureReason.fileNotFound:
                title = strings.fileFailedToDownload;
                message = strings.tryAgainDownloadingFile;
                break;
              case FileDownloadFailureReason.networkConnectionError:
                title = strings.fileFailedToDownload;
                message = strings.multiDownloadErrorTryAgain;
                break;
              default:
                title = strings.fileFailedToDownload;
                message = strings.fileDownloadFailed;
            }

            return ArDriveStandardModalNew(
              width: _width,
              title: title,
              content: ArDriveNotice(
                type: ArDriveNoticeType.error,
                message: message,
              ),
              actions: [
                // Cancel stops the download as well as closing the dialog.
                ModalAction.dismiss(
                  action: () {
                    context
                        .read<MultipleDownloadBloc>()
                        .add(const CancelDownload());
                    Navigator.pop(context);
                  },
                  title: strings.cancel,
                ),
                if (showRetryAndSkip) ...[
                  ModalAction.dismiss(
                    action: () {
                      context
                          .read<MultipleDownloadBloc>()
                          .add(const SkipFileAndResumeDownload());
                    },
                    title: strings.skip,
                  ),
                  ModalAction(
                    action: () {
                      context
                          .read<MultipleDownloadBloc>()
                          .add(const ResumeDownload());
                    },
                    title: strings.tryAgain,
                  ),
                ]
              ],
            );
          }

          // Before the first answer: a wait, not a sentence.
          return ArDriveStandardModalNew(
            width: _width,
            title: appLocalizationsOf(context).download,
            content: const Center(
              child: ArDriveSpinner(size: ArDriveSpinnerSize.large),
            ),
            actions: [
              ModalAction.close(
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
