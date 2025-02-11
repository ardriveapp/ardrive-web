import 'package:ardrive/blocs/bulk_import/bulk_import_bloc.dart';
import 'package:ardrive/blocs/bulk_import/bulk_import_event.dart';
import 'package:ardrive/blocs/bulk_import/bulk_import_state.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
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
    if (value.length != 43) {
      return 'Invalid manifest transaction ID';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);

    return BlocConsumer<BulkImportBloc, BulkImportState>(
      listener: (context, state) {
        if (state is BulkImportSuccess) {
          showArDriveDialog(
            context,
            content: ArDriveStandardModalNew(
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
                  action: () => Navigator.pop(context),
                  title: 'OK',
                ),
              ],
            ),
          );
        } else if (state is BulkImportFileConflicts) {
          showArDriveDialog(
            context,
            content: ArDriveStandardModalNew(
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
                    style: typography.paragraphNormal(),
                  ),
                ],
              ),
              actions: [
                ModalAction(
                  action: () => Navigator.pop(context),
                  title: 'Cancel',
                ),
                ModalAction(
                  action: () {
                    context.read<BulkImportBloc>().add(
                          ReplaceConflictingFiles(
                            manifestTxId: _manifestTxIdController.text,
                            driveId: widget.driveId,
                            parentFolderId: widget.parentFolderId,
                          ),
                        );

                    // Replace action will be implemented in the next prompt
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
        }
      },
      builder: (context, state) {
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
                  Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Loading manifest data...',
                        style: typography.paragraphNormal(),
                      ),
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
              action: () => Navigator.pop(context),
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
