import 'package:ardrive/blocs/bulk_import/bulk_import_bloc.dart';
import 'package:ardrive/turbo/topup/views/topup_modal.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/blocs/bulk_import/bulk_import_event.dart';
import 'package:ardrive/blocs/bulk_import/bulk_import_state.dart';
import 'package:ardrive/core/arfs/use_cases/bulk_import_files.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/validate_arweave_id.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Modal for importing files from a manifest.
class BulkImportModal extends StatelessWidget {
  final String driveId;
  final String parentFolderId;

  const BulkImportModal({
    super.key,
    required this.driveId,
    required this.parentFolderId,
  });

  @override
  Widget build(BuildContext context) {
    return _BulkImportModalContent(
      driveId: driveId,
      parentFolderId: parentFolderId,
    );
  }
}

class _BulkImportModalContent extends StatefulWidget {
  final String driveId;
  final String parentFolderId;

  const _BulkImportModalContent({
    required this.driveId,
    required this.parentFolderId,
  });

  @override
  State<_BulkImportModalContent> createState() =>
      _BulkImportModalContentState();
}

class _BulkImportModalContentState extends State<_BulkImportModalContent> {
  final _formKey = GlobalKey<FormState>();
  final _manifestTxIdController = TextEditingController();

  /// Import was pressed and the bloc has not answered with a state yet: the
  /// field is held and a second press does nothing.
  bool _pressed = false;

  @override
  void dispose() {
    _manifestTxIdController.dispose();
    super.dispose();
  }

  String? _validateManifestTxId(String? value) {
    final l10n = appLocalizationsOf(context);
    if (value == null || value.isEmpty) {
      return l10n.importIdRequired;
    }
    // Arweave transaction IDs are 43 characters long and base64url encoded
    if (!isArweaveTransactionID(value)) {
      return l10n.importIdInvalid;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final l10n = appLocalizationsOf(context);

    // Every outcome is a state of this one dialog, never a dialog over it:
    // the conflicts, the failure and the cancelled import used to open on
    // top, and the conflicts' Cancel closed both.
    return BlocConsumer<BulkImportBloc, BulkImportState>(
      listener: (context, state) {
        if (_pressed) setState(() => _pressed = false);
      },
      builder: (context, state) {
        if (state is BulkImportSuccess) {
          return ArDriveStandardModalNew(
            width: kMediumDialogWidth,
            title: l10n.importSuccessTitle,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.importSuccessBody(state.successfulFiles),
                  style: typography.paragraphNormal(),
                ),
                if (state.failedFiles != 0)
                  Text(
                    l10n.importFilesFailed(state.failedFiles),
                    style: typography.paragraphNormal(),
                  ),
              ],
            ),
            actions: [
              ModalAction.close(
                action: () => Navigator.pop(context),
                title: l10n.close,
              ),
            ],
          );
        } else if (state is BulkImportFileConflicts) {
          return ArDriveStandardModalNew(
            width: kLargeDialogWidth,
            scrollableContent: true,
            title: l10n.importConflictsTitle,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.importConflictsBody,
                  style: typography.paragraphNormal(
                    color:
                        ArDriveTheme.of(context).themeData.colorTokens.textMid,
                  ),
                ),
                const SizedBox(height: ArDriveSpacing.md),
                for (final conflict in state.conflicts)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: ArDriveSpacing.xxs),
                    child: Text(
                      conflict.filePath,
                      style: typography.paragraphNormal(),
                    ),
                  ),
                const SizedBox(height: ArDriveSpacing.md),
                Text(
                  l10n.importConflictsQuestion,
                  style: typography.paragraphLarge(
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
              ],
            ),
            actions: [
              ModalAction.close(
                action: () => Navigator.pop(context),
                title: l10n.cancelEmphasized,
              ),
              ModalAction(
                action: () {
                  context.read<BulkImportBloc>().add(
                        ReplaceConflictingFiles(
                          manifestTxId: state.manifestTxId,
                          driveId: widget.driveId,
                          parentFolderId: widget.parentFolderId,
                        ),
                      );
                },
                title: l10n.importReplace,
              ),
            ],
          );
        } else if (state is BulkImportCancelled) {
          return ArDriveStandardModalNew(
            width: kMediumDialogWidth,
            title: l10n.importCancelledTitle,
            description: l10n.importCancelledBody(state.numberOfFilesImported),
            actions: [
              ModalAction.close(
                action: () => Navigator.pop(context),
                title: l10n.close,
              ),
            ],
          );
        } else if (state is BulkImportReviewingManifest) {
          return ArDriveStandardModalNew(
            title: l10n.importReviewTitle,
            width: kLargeDialogWidth,
            scrollableContent: true,
            content: _BulkImportReviewingManifest(
              manifestTxId: state.manifestTxId,
              files: state.files,
            ),
            actions: [
              ModalAction.close(
                action: () => Navigator.pop(context),
                title: l10n.cancelEmphasized,
              ),
              ModalAction(
                action: () {
                  context.read<BulkImportBloc>().add(
                        ConfirmManifestBulkImport(
                          manifestTxId: state.manifestTxId,
                          driveId: widget.driveId,
                          parentFolderId: widget.parentFolderId,
                          files: state.files,
                        ),
                      );
                },
                title: l10n.importAction,
              ),
            ],
          );
        }

        // The work runs here: the primary is busy, the fields are gone for
        // the progress, and Cancel is held unless it can stop the work.
        final isImporting = state is BulkImportInProgress;
        final isBusy = _pressed ||
            isImporting ||
            state is BulkImportLoadingManifest ||
            state is BulkImportResolvingPaths ||
            state is BulkImportCreatingFolders;

        return ArDriveStandardModalNew(
          width: kLargeDialogWidth,
          title: l10n.importFromDeployment,
          content: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state is BulkImportError) ...[
                  ArDriveNotice(
                    type: ArDriveNoticeType.error,
                    message: _errorText(l10n, state),
                    actionLabel: state.isPaymentError ? l10n.buyCredits : null,
                    onAction: state.isPaymentError
                        ? () {
                            Navigator.pop(context);
                            showTurboTopupModal(context);
                          }
                        : null,
                  ),
                  const SizedBox(height: ArDriveSpacing.md),
                ],
                if (state is BulkImportLoadingManifest)
                  _ImportProgress(
                    title: l10n.importLoading,
                  )
                else if (state is BulkImportResolvingPaths)
                  _ImportProgress(
                    title: l10n.importResolving,
                    value: state.totalPaths == 0
                        ? null
                        : state.processedPaths / state.totalPaths,
                    detail: l10n.importProgress(
                      state.processedPaths,
                      state.totalPaths,
                    ),
                  )
                else if (state is BulkImportCreatingFolders)
                  _ImportProgress(
                    title: l10n.importCreatingFolder(state.currentFolderPath),
                    value: state.totalFolders == 0
                        ? null
                        : state.processedFolders / state.totalFolders,
                    detail: l10n.importProgress(
                      state.processedFolders,
                      state.totalFolders,
                    ),
                  )
                else if (state is BulkImportInProgress)
                  _ImportProgress(
                    title: l10n.importingFile(state.currentFileName),
                    value: state.fileIds.isEmpty
                        ? null
                        : state.processedFiles / state.fileIds.length,
                    detail: l10n.importProgress(
                      state.processedFiles,
                      state.fileIds.length,
                    ),
                    extra: state.failedPaths.isNotEmpty
                        ? l10n.importFilesFailed(state.failedPaths.length)
                        : null,
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.importEnterId,
                        style: typography.paragraphNormal(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colorTokens
                              .textMid,
                        ),
                      ),
                      const SizedBox(height: ArDriveSpacing.md),
                      ArDriveTextFieldNew(
                        controller: _manifestTxIdController,
                        isEnabled: !isBusy,
                        validator: _validateManifestTxId,
                        label: l10n.importDeploymentIdLabel,
                        textStyle: ArDriveTypographyNew.of(context).code(),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            if (isImporting)
              // Stops the import, then closes: it does more than close.
              ModalAction.dismiss(
                action: () {
                  context.read<BulkImportBloc>().add(const CancelBulkImport());
                  Navigator.pop(context);
                },
                title: l10n.cancelEmphasized,
              )
            else
              ModalAction.close(
                isEnable: !isBusy,
                action: () => Navigator.pop(context),
                title: l10n.cancelEmphasized,
              ),
            ModalAction(
              isLoading: isBusy,
              action: () {
                if (_pressed) return;
                if (_formKey.currentState!.validate()) {
                  setState(() => _pressed = true);
                  context.read<BulkImportBloc>().add(
                        StartManifestBulkImport(
                          manifestTxId: _manifestTxIdController.text,
                          driveId: widget.driveId,
                          parentFolderId: widget.parentFolderId,
                        ),
                      );
                }
              },
              title: l10n.importAction,
            ),
          ],
        );
      },
    );
  }
}

/// What an import failure says, in the user's language. The bloc's own
/// sentence is English, for the log.
String _errorText(AppLocalizations l10n, BulkImportError state) {
  if (state.isPaymentError) return l10n.freeAllowanceUsedUpDescription;
  return switch (state.reason) {
    BulkImportErrorReason.notFound => l10n.importErrorNotFound,
    BulkImportErrorReason.network => l10n.importErrorNetwork,
    BulkImportErrorReason.unreadable => l10n.importErrorUnreadable,
    BulkImportErrorReason.noFilesToReplace => l10n.importErrorNoFilesToReplace,
    BulkImportErrorReason.replaceFailed => l10n.importErrorReplaceFailed,
    BulkImportErrorReason.importFailed => l10n.importErrorImportFailed,
    BulkImportErrorReason.nothingImported => l10n.importErrorNothingImported,
    BulkImportErrorReason.unexpected => l10n.importErrorUnexpected,
  };
}

/// What the import is doing: a spinner or a bar, what it is on, and how far.
class _ImportProgress extends StatelessWidget {
  const _ImportProgress({
    required this.title,
    this.value,
    this.detail,
    this.extra,
  });

  final String title;

  /// Null spins; a value from 0 to 1 fills the bar.
  final double? value;
  final String? detail;
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (value != null)
          ArDriveLinearProgress(value: value)
        else
          const Center(child: ArDriveSpinner(size: ArDriveSpinnerSize.large)),
        const SizedBox(height: ArDriveSpacing.md),
        Text(
          title,
          textAlign: TextAlign.center,
          style: typography.paragraphNormal(),
        ),
        if (detail != null)
          Text(
            detail!,
            textAlign: TextAlign.center,
            style: typography.paragraphNormal(),
          ),
        if (extra != null) ...[
          const SizedBox(height: ArDriveSpacing.md),
          Text(
            extra!,
            textAlign: TextAlign.center,
            style: typography.paragraphNormal(),
          ),
        ],
      ],
    );
  }
}

class _BulkImportReviewingManifest extends StatelessWidget {
  final String manifestTxId;
  final List<ManifestFileEntry> files;

  const _BulkImportReviewingManifest(
      {required this.manifestTxId, required this.files});

  @override
  Widget build(BuildContext context) {
    // Build a folder tree from the file paths
    final FolderNode rootFolder = _buildFolderTree(files);

    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    // No box of its own height: the dialog scrolls, with its actions held.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          appLocalizationsOf(context).importReviewSummary(files.length),
          style: typography.paragraphNormal(color: colorTokens.textMid),
        ),
        const SizedBox(height: ArDriveSpacing.md),
        _buildFolderTreeView(context, rootFolder, 0),
      ],
    );
  }

  // Build a tree structure from file paths
  FolderNode _buildFolderTree(List<ManifestFileEntry> files) {
    final FolderNode root = FolderNode(name: 'Root', path: '');

    for (final file in files) {
      // Split the path into components
      final pathParts = file.path.split('/');

      // Remove empty parts (e.g., if path starts with /)
      final parts = pathParts.where((part) => part.isNotEmpty).toList();

      // Start at the root folder
      FolderNode currentFolder = root;

      // Create folders as needed, excluding the last part (which is the file name)
      for (int i = 0; i < parts.length - 1; i++) {
        final folderName = parts[i];
        final folderPath = parts.sublist(0, i + 1).join('/');

        // Check if the folder already exists in the current folder
        FolderNode? folder;
        try {
          folder =
              currentFolder.subfolders.firstWhere((f) => f.name == folderName);
        } catch (_) {
          // Folder does not exist, create it
          folder = FolderNode(name: folderName, path: folderPath);
          currentFolder.subfolders.add(folder);
        }

        // Move to the next level
        currentFolder = folder;
      }

      // Add the file to the last folder
      currentFolder.files.add(file);
    }

    return root;
  }

  // Build the tree view UI
  Widget _buildFolderTreeView(
      BuildContext context, FolderNode folder, int level) {
    // For the root node, just display its children
    if (folder.name == 'Root') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Build all subfolders
          ...folder.subfolders
              .map((subfolder) => _buildFolderItem(context, subfolder, level)),

          // Build files directly in root
          ...folder.files.map((file) => _FileTile(
                file: file,
                level: level + 1,
              )),
        ],
      );
    }

    return _buildFolderItem(context, folder, level);
  }

  // Build a folder item: its name, then what is in it, indented.
  Widget _buildFolderItem(BuildContext context, FolderNode folder, int level) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return Padding(
      padding: EdgeInsets.only(left: ArDriveSpacing.md * level),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ArDriveSpacing.xs),
            child: Row(
              children: [
                ArDriveIcons.folderOutline(color: colorTokens.textHigh),
                const SizedBox(width: ArDriveSpacing.xs),
                Expanded(
                  child: Text(
                    folder.name,
                    style: typography.paragraphNormal(
                      fontWeight: ArFontWeight.semiBold,
                      color: colorTokens.textHigh,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...folder.subfolders.map(
            (subfolder) => _buildFolderItem(context, subfolder, 1),
          ),
          ...folder.files.map((file) => _FileTile(file: file, level: 1)),
        ],
      ),
    );
  }
}

// Model class for folder nodes
class FolderNode {
  final String name;
  final String path;
  final List<FolderNode> subfolders = [];
  final List<ManifestFileEntry> files = [];

  FolderNode({required this.name, required this.path});
}

// Widget for a file tile
class _FileTile extends StatelessWidget {
  final ManifestFileEntry file;
  final int level;

  const _FileTile({required this.file, required this.level});

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: ArDriveSpacing.md * level,
        right: ArDriveSpacing.xs,
        top: ArDriveSpacing.xs,
        bottom: ArDriveSpacing.xs,
      ),
      child: Row(
        children: [
          getIconForContentType(file.contentType),
          const SizedBox(width: ArDriveSpacing.xs),
          Expanded(
            child: Text(
              file.name,
              style: typography.paragraphNormal(),
            ),
          ),
        ],
      ),
    );
  }
}
