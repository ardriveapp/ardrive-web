import 'package:ardrive/blocs/note_create/note_create_cubit.dart';
import 'package:ardrive/blocs/note_create/note_create_state.dart';
import 'package:ardrive/components/upload_form.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'note_editor_widget.dart';

/// Entry point function to show note creation dialog
Future<void> promptToCreateNote(
  BuildContext context, {
  required String driveId,
  required String parentFolderId,
}) async {
  final ioFile = await showArDriveDialogWithBuilder<IOFile>(
    context,
    builder: (context) => BlocProvider(
      create: (context) => NoteCreateCubit(
        driveId: driveId,
        parentFolderId: parentFolderId,
      ),
      child: const NoteCreateForm(),
    ),
    barrierDismissible: false, // Prevent accidental dismissal
  );

  // If user completed the note creation, show upload flow
  if (ioFile != null && context.mounted) {
    await promptToUpload(
      context,
      driveId: driveId,
      parentFolderId: parentFolderId,
      isFolderUpload: false,
      files: [ioFile],
    );
  }
}

/// Entry point function to edit an existing markdown note
Future<void> promptToEditNote(
  BuildContext context, {
  required String driveId,
  required String parentFolderId,
  required String fileId,
  required String fileName,
  required String fileContent,
  required int fileSize,
}) async {
  // Block files over 5MB
  const maxFileSize = 5 * 1024 * 1024; // 5MB
  const warnFileSize = 1 * 1024 * 1024; // 1MB

  if (fileSize > maxFileSize) {
    final fileSizeMB = (fileSize / 1024 / 1024).toStringAsFixed(1);
    await showStandardDialog(
      context,
      title: appLocalizationsOf(context).error,
      description: appLocalizationsOf(context).noteFileTooLarge(fileSizeMB),
      actions: [
        ModalAction(
          action: () => Navigator.of(context).pop(),
          title: appLocalizationsOf(context).okEmphasized,
        ),
      ],
    );
    return;
  }

  // Warn for files over 1MB
  if (fileSize > warnFileSize && context.mounted) {
    final fileSizeMB = (fileSize / 1024 / 1024).toStringAsFixed(1);
    final proceed = await showArDriveDialogWithBuilder<bool>(
      context,
      builder: (context) => ArDriveStandardModalNew(
        title: appLocalizationsOf(context).noteLargeFileWarningTitle,
        description: appLocalizationsOf(context)
            .noteLargeFileWarningDescription(fileSizeMB),
        actions: [
          ModalAction(
            action: () => Navigator.of(context).pop(false),
            title: appLocalizationsOf(context).cancelEmphasized,
          ),
          ModalAction(
            action: () => Navigator.of(context).pop(true),
            title: appLocalizationsOf(context).continueEmphasized,
          ),
        ],
      ),
    );

    if (proceed != true) return;
  }

  if (!context.mounted) return;

  final ioFile = await showArDriveDialogWithBuilder<IOFile>(
    context,
    builder: (context) => BlocProvider(
      create: (context) => NoteCreateCubit(
        driveId: driveId,
        parentFolderId: parentFolderId,
        existingFileId: fileId,
        initialName: fileName.endsWith('.md')
            ? fileName.substring(0, fileName.length - 3)
            : fileName,
        initialContent: fileContent,
      ),
      child: const NoteCreateForm(),
    ),
    barrierDismissible: false,
  );

  // If user saved the edited note, show upload flow
  // Auto-replace the existing file without showing conflict modal
  if (ioFile != null && context.mounted) {
    logger.d(
        'promptToEditNote: Showing upload modal for edited note: ${ioFile.name}');
    await promptToUpload(
      context,
      driveId: driveId,
      parentFolderId: parentFolderId,
      isFolderUpload: false,
      files: [ioFile],
      autoReplaceConflicts: true, // Auto-replace when editing markdown
    );
  } else {
    logger.w(
        'promptToEditNote: Not showing upload modal - ioFile: ${ioFile != null}, context.mounted: ${context.mounted}');
  }
}

/// Modal form for creating a new markdown note
class NoteCreateForm extends StatefulWidget {
  const NoteCreateForm({super.key});

  @override
  State<NoteCreateForm> createState() => _NoteCreateFormState();
}

class _NoteCreateFormState extends State<NoteCreateForm> {
  final _nameController = TextEditingController();
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    // Populate name controller with initial name from cubit (for edit mode)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cubit = context.read<NoteCreateCubit>();
      final state = cubit.state;
      if (state is NoteCreateEditing && state.noteName.isNotEmpty) {
        _nameController.text = state.noteName;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges) return true;

    final result = await showArDriveDialogWithBuilder<bool>(
      context,
      builder: (context) => ArDriveStandardModalNew(
        title: appLocalizationsOf(context).discardChanges,
        description: appLocalizationsOf(context).discardChangesDescription,
        actions: [
          ModalAction(
            action: () => Navigator.of(context).pop(false),
            title: appLocalizationsOf(context).cancelEmphasized,
          ),
          ModalAction(
            action: () => Navigator.of(context).pop(true),
            title: appLocalizationsOf(context).discardEmphasized,
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> _createNote() async {
    final cubit = context.read<NoteCreateCubit>();
    logger.d('_createNote called, isEditMode: ${cubit.isEditMode}');

    final ioFile = await cubit.createNoteFile();

    if (ioFile == null) {
      logger.w('createNoteFile returned null, not proceeding');
      return;
    }

    logger.d('Created note file: ${ioFile.name}, closing modal');

    // Close this modal and return the file to the caller
    if (!mounted) return;
    Navigator.of(context).pop(ioFile);
  }

  bool _isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  double _getResponsiveWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    // Mobile: Use most of screen width with padding
    if (screenWidth < 600) {
      return screenWidth - 32; // 16px padding on each side
    }
    // Tablet: Use a reasonable width
    else if (screenWidth < 1024) {
      return 700;
    }
    // Desktop: Use wider width for comfortable split view
    else {
      return 900;
    }
  }

  double _getResponsiveEditorHeight(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    // Mobile: Adjust height to fit viewport better
    if (screenHeight < 700) {
      return 300;
    }
    // Tablet/Desktop: Use comfortable height
    else {
      return 450;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<NoteCreateCubit, NoteCreateState>(
      listener: (context, state) async {
        if (state is NoteCreateError) {
          await showStandardDialog(
            context,
            title: appLocalizationsOf(context).error,
            description: _getCreateErrorMessage(context, state.errorKey),
            actions: [
              ModalAction(
                action: () => Navigator.of(context).pop(),
                title: appLocalizationsOf(context).okEmphasized,
              ),
            ],
          );
        }
      },
      builder: (context, state) {
        if (state is! NoteCreateEditing) {
          return const SizedBox.shrink();
        }

        // Track unsaved changes
        _hasUnsavedChanges =
            state.noteName.isNotEmpty || state.content.isNotEmpty;

        return PopScope(
          canPop: false,
          onPopInvoked: (didPop) async {
            if (didPop) return;
            final navigator = Navigator.of(context);
            final shouldPop = await _confirmDiscard();
            if (shouldPop && mounted) {
              navigator.pop();
            }
          },
          child: _isMobile(context)
              ? _buildMobileLayout(context, state)
              : _buildDesktopLayout(context, state),
        );
      },
    );
  }

  /// Build full-page mobile layout
  Widget _buildMobileLayout(BuildContext context, NoteCreateEditing state) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final cubit = context.read<NoteCreateCubit>();
    final isEditMode = cubit.isEditMode;

    return Scaffold(
      backgroundColor: colorTokens.containerL0,
      appBar: AppBar(
        backgroundColor: colorTokens.containerL0,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: colorTokens.iconHigh),
          tooltip: appLocalizationsOf(context).close,
          onPressed: () async {
            final navigator = Navigator.of(context);
            if (await _confirmDiscard()) {
              if (mounted) navigator.pop();
            }
          },
        ),
        title: Text(
          isEditMode
              ? appLocalizationsOf(context).editNote
              : appLocalizationsOf(context).createNewNote,
          style: typography.heading5(
            color: colorTokens.textHigh,
            fontWeight: ArFontWeight.bold,
          ),
        ),
        actions: [
          Center(
            child: ArDriveButtonNew(
              text: appLocalizationsOf(context).nextEmphasized,
              typography: typography,
              variant: ButtonVariant.primary,
              size: ArDriveButtonSize.compact,
              isDisabled: !state.isValidName,
              onPressed: state.isValidName ? _createNote : null,
            ),
          ),
          const SizedBox(width: ArDriveSpacing.md),
        ],
      ),
      body: _buildMobileContent(context, state),
    );
  }

  /// Build desktop/tablet modal layout
  Widget _buildDesktopLayout(BuildContext context, NoteCreateEditing state) {
    final modalWidth = _getResponsiveWidth(context);
    final cubit = context.read<NoteCreateCubit>();
    final isEditMode = cubit.isEditMode;

    return ArDriveStandardModalNew(
      width: modalWidth,
      title: isEditMode
          ? appLocalizationsOf(context).editNote
          : appLocalizationsOf(context).createNewNote,
      content: _buildContent(context, state, modalWidth),
      actions: [
        ModalAction(
          action: () async {
            final navigator = Navigator.of(context);
            if (await _confirmDiscard()) {
              if (mounted) navigator.pop();
            }
          },
          title: appLocalizationsOf(context).cancelEmphasized,
        ),
        ModalAction(
          action: _createNote,
          title: appLocalizationsOf(context).nextEmphasized,
          isEnable: state.isValidName,
        ),
      ],
    );
  }

  /// Build mobile-optimized content (full height)
  Widget _buildMobileContent(BuildContext context, NoteCreateEditing state) {
    return Padding(
      padding: const EdgeInsets.all(ArDriveSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildNameField(context, state),
          const SizedBox(height: ArDriveSpacing.md),

          // Markdown editor - takes remaining space
          Expanded(
            child: NoteEditorWidget(
              initialContent: state.content,
              onChanged: (content) {
                context.read<NoteCreateCubit>().updateContent(content);
              },
              viewMode: state.viewMode,
              onViewModeChanged: (mode) {
                context.read<NoteCreateCubit>().setViewMode(mode);
              },
              isMobile: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, NoteCreateEditing state, double modalWidth) {
    final editorHeight = _getResponsiveEditorHeight(context);

    return SizedBox(
      width: modalWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildNameField(context, state),
          const SizedBox(height: ArDriveSpacing.md),

          // Markdown editor
          SizedBox(
            height: editorHeight,
            child: NoteEditorWidget(
              initialContent: state.content,
              onChanged: (content) {
                context.read<NoteCreateCubit>().updateContent(content);
              },
              viewMode: state.viewMode,
              onViewModeChanged: (NoteViewMode mode) {
                context.read<NoteCreateCubit>().setViewMode(mode);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The name, labelled the way [ArDriveTextFieldNew] labels a field. The
  /// label and error sit outside the field so that ".md" lines up with the
  /// box rather than with the box and its label together.
  Widget _buildNameField(BuildContext context, NoteCreateEditing state) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final cubit = context.read<NoteCreateCubit>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: ArDriveSpacing.xxs),
          child: Text(
            appLocalizationsOf(context).noteName,
            style: typography.paragraphNormal(
              color: colorTokens.textLow,
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: ArDriveTextFieldNew(
                key: const Key('note_name_text_field'),
                controller: _nameController,
                onChanged: cubit.isEditMode
                    ? null
                    : (value) {
                        context.read<NoteCreateCubit>().updateNoteName(value);
                      },
                hintText: appLocalizationsOf(context).enterNoteName,
                autofocus: !cubit.isEditMode,
                isEnabled: !cubit.isEditMode,
              ),
            ),
            const SizedBox(width: ArDriveSpacing.xs),
            Text(
              '.md',
              style: typography.paragraphNormal(color: colorTokens.textLow),
            ),
          ],
        ),
        if (state.nameError != null)
          Padding(
            padding: const EdgeInsets.only(top: ArDriveSpacing.xs),
            child: Text(
              _getErrorMessage(context, state.nameError!),
              style: typography.paragraphNormal(
                color: colorTokens.statusErrorFg,
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
          ),
      ],
    );
  }

  /// Resolves error key to localized error message
  String _getErrorMessage(
      BuildContext context, NoteNameValidationError errorKey) {
    switch (errorKey) {
      case NoteNameValidationError.empty:
        return appLocalizationsOf(context).noteNameEmptyError;
      case NoteNameValidationError.invalidCharacters:
        return appLocalizationsOf(context).noteNameInvalidCharactersError;
    }
  }

  /// Resolves note creation error key to localized error message
  String _getCreateErrorMessage(
      BuildContext context, NoteCreateErrorKey errorKey) {
    switch (errorKey) {
      case NoteCreateErrorKey.createFileFailed:
        return appLocalizationsOf(context).noteCreateFileFailed;
    }
  }
}
