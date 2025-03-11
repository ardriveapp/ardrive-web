import 'package:ardrive/blocs/bulk_import/bulk_import_bloc.dart';
import 'package:ardrive/blocs/bulk_import/bulk_import_event.dart';
import 'package:ardrive/blocs/bulk_import/bulk_import_state.dart';
import 'package:ardrive/core/arfs/use_cases/bulk_import_files.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/validate_arweave_id.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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

  @override
  void dispose() {
    _manifestTxIdController.dispose();
    super.dispose();
  }

  String? _validateManifestTxId(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a manifest transaction ID';
    }
    // Arweave transaction IDs are 43 characters long and base64url encoded
    if (!isArweaveTransactionID(value)) {
      return 'Invalid manifest transaction ID';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);

    return BlocConsumer<BulkImportBloc, BulkImportState>(
      listener: (context, state) {
        if (state is BulkImportFileConflicts) {
          showAnimatedDialogWithBuilder(
            context,
            builder: (context) => ArDriveStandardModalNew(
              width: kLargeDialogWidth,
              title: 'File Conflicts Detected',
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The following files already exist in the target location:',
                    style: typography.paragraphLarge(),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: state.conflicts.map((conflict) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              '• ${conflict.filePath}',
                              style: typography.paragraphNormal(),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Would you like to replace these files?',
                    style: typography.paragraphLarge(
                      fontWeight: ArFontWeight.semiBold,
                    ),
                  ),
                ],
              ),
              actions: [
                ModalAction(
                  action: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                  title: 'Cancel',
                ),
                ModalAction(
                  action: () {
                    this.context.read<BulkImportBloc>().add(
                          ReplaceConflictingFiles(
                            manifestTxId: _manifestTxIdController.text,
                            driveId: widget.driveId,
                            parentFolderId: widget.parentFolderId,
                          ),
                        );

                    Navigator.pop(context);
                  },
                  title: 'Replace',
                ),
              ],
            ),
          );
        } else if (state is BulkImportError) {
          showArDriveDialog(
            context,
            content: ArDriveStandardModalNew(
              width: kLargeDialogWidth,
              title: 'Import Failed',
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.message,
                    style: typography.paragraphNormal(),
                  ),
                ],
              ),
              actions: [
                ModalAction(
                  action: () => Navigator.pop(context),
                  title: 'OK',
                ),
              ],
            ),
          );
        } else if (state is BulkImportCancelled) {
          final numberOfFilesImported = state.numberOfFilesImported;

          showAnimatedDialogWithBuilder(
            context,
            builder: (context) => ArDriveStandardModalNew(
              width: kMediumDialogWidth,
              title: 'Import Cancelled',
              description:
                  'The import process was cancelled.\n$numberOfFilesImported files were imported successfully.',
              actions: [
                ModalAction(
                  action: () => Navigator.pop(context),
                  title: 'OK',
                ),
              ],
            ),
          );
        }
      },
      builder: (context, state) {
        if (state is BulkImportSuccess) {
          return ArDriveStandardModalNew(
            width: modalStandardMaxWidthSize,
            title: 'Import Successful',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Successfully imported ${state.successfulFiles} files.',
                  style: typography.paragraphNormal(),
                ),
                if (state.failedFiles != 0)
                  Text(
                    'Failed to import ${state.failedFiles} files.',
                    style: typography.paragraphNormal(),
                  ),
              ],
            ),
            actions: [
              ModalAction(
                action: () {
                  Navigator.pop(context);
                },
                title: 'OK',
              ),
            ],
          );
        } else if (state is BulkImportReviewingManifest) {
          return ArDriveStandardModalNew(
            title: 'Review Files',
            width: kLargeDialogWidth,
            content: _BulkImportReviewingManifest(
              manifestTxId: state.manifestTxId,
              files: state.files,
            ),
            actions: [
              ModalAction(
                action: () {
                  Navigator.pop(context);
                },
                title: 'Cancel',
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
                title: 'Confirm',
              ),
            ],
          );
        }

        return ArDriveStandardModalNew(
          width: kLargeDialogWidth,
          title: 'Import from Manifest',
          content: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state is BulkImportLoadingManifest)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Text(
                        'Loading manifest data...',
                        style: typography.paragraphLarge(
                          fontWeight: ArFontWeight.semiBold,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const CircularProgressIndicator(),
                    ],
                  )
                else if (state is BulkImportResolvingPaths)
                  Column(
                    children: [
                      LinearProgressIndicator(
                        value: state.processedPaths / state.totalPaths,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Resolving file paths...',
                        style: typography.paragraphNormal(),
                      ),
                      Text(
                        'Progress: ${state.processedPaths}/${state.totalPaths}',
                        style: typography.paragraphNormal(),
                      ),
                    ],
                  )
                else if (state is BulkImportCreatingFolders)
                  Column(
                    children: [
                      LinearProgressIndicator(
                        value: state.processedFolders / state.totalFolders,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Creating folder: ${state.currentFolderPath}',
                        style: typography.paragraphNormal(),
                      ),
                      Text(
                        'Progress: ${state.processedFolders}/${state.totalFolders}',
                        style: typography.paragraphNormal(),
                      ),
                    ],
                  )
                else if (state is BulkImportInProgress)
                  Column(
                    children: [
                      LinearProgressIndicator(
                        value: state.processedFiles / state.fileIds.length,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Importing ${state.currentFileName}...',
                        style: typography.paragraphNormal(),
                      ),
                      Text(
                        'Progress: ${state.processedFiles}/${state.fileIds.length}',
                        style: typography.paragraphNormal(),
                      ),
                      if (state.failedPaths.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Failed files: ${state.failedPaths.length}',
                          style: typography.paragraphNormal(),
                        ),
                      ],
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Enter the manifest transaction ID to import files:',
                        style: typography.paragraphNormal(),
                      ),
                      const SizedBox(height: 16),
                      ArDriveTextFieldNew(
                        controller: _manifestTxIdController,
                        validator: _validateManifestTxId,
                        label: 'Manifest Transaction ID',
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            ModalAction(
              action: () {
                if (state is BulkImportInProgress) {
                  context.read<BulkImportBloc>().add(const CancelBulkImport());
                }
                Navigator.pop(context);
              },
              title: 'Cancel',
            ),
            if (state is! BulkImportLoadingManifest &&
                state is! BulkImportInProgress)
              ModalAction(
                action: () {
                  if (_formKey.currentState!.validate()) {
                    context.read<BulkImportBloc>().add(
                          StartManifestBulkImport(
                            manifestTxId: _manifestTxIdController.text,
                            driveId: widget.driveId,
                            parentFolderId: widget.parentFolderId,
                          ),
                        );
                  }
                },
                title: 'Import',
              ),
          ],
        );
      },
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

    return SizedBox(
      width: kLargeDialogWidth,
      height: 400,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The following files will be imported:',
            style: typography.paragraphLarge(
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      _buildFolderTreeView(context, rootFolder, 0),
                    ],
                  ),
                ),
                const Divider(height: 8),
                Text(
                  '${files.length} file(s) will be imported',
                  style: typography.paragraphLarge(
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

  // Build a folder item with ExpansionTile
  Widget _buildFolderItem(BuildContext context, FolderNode folder, int level) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return Padding(
      padding: EdgeInsets.only(left: 16.0 * level),
      child: ExpansionTile(
        title: Text(
          folder.name,
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.semiBold,
          ),
        ),
        textColor: colorTokens.textHigh,
        leading: ArDriveIcons.folderOutline(),
        initiallyExpanded: true,
        maintainState: true,
        children: [
          // Build subfolders
          ...folder.subfolders.map((subfolder) => _buildFolderItem(
                context,
                subfolder,
                1, // Add level 1 for consistent indentation of subfolders
              )),

          // Build files
          ...folder.files.map((file) => _FileTile(
                file: file,
                level: 1, // Add level 1 for consistent indentation of files
              )),
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
        left: 16.0 * level,
        right: 8.0,
        top: 8.0,
        bottom: 8.0,
      ),
      child: Row(
        children: [
          const SizedBox(width: 24), // Align with folder content
          getIconForContentType(file.contentType),
          const SizedBox(width: 8),
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
