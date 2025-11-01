import 'package:ardrive/blocs/note_create/note_create_cubit.dart';
import 'package:ardrive/blocs/note_create/note_create_state.dart';
import 'package:ardrive/components/upload_form.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
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
  final ioFile = await showAnimatedDialogWithBuilder<IOFile>(
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
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges) return true;

    final result = await showAnimatedDialogWithBuilder<bool>(
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
    final ioFile = await cubit.createNoteFile();

    if (ioFile == null) return;

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
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);
    final cubit = context.read<NoteCreateCubit>();
    final isEditMode = cubit.isEditMode;

    return Scaffold(
      backgroundColor: colors.themeBgSurface,
      appBar: AppBar(
        backgroundColor: colors.themeBgSurface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: colors.themeFgDefault),
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
            color: colors.themeFgDefault,
          ),
        ),
        actions: [
          TextButton(
            onPressed: state.isValidName ? _createNote : null,
            child: Text(
              isEditMode
                  ? appLocalizationsOf(context).saveEmphasized
                  : appLocalizationsOf(context).nextEmphasized,
              style: typography.paragraphNormal(
                color: state.isValidName
                    ? colors.themeAccentBrand
                    : colors.themeFgDisabled,
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
          ),
          const SizedBox(width: 8),
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
          customWidth: 100,
          customHeight: 40,
        ),
        ModalAction(
          action: _createNote,
          title: isEditMode
              ? appLocalizationsOf(context).saveEmphasized
              : appLocalizationsOf(context).nextEmphasized,
          isEnable: state.isValidName,
          customWidth: 100,
          customHeight: 40,
        ),
      ],
    );
  }

  /// Build mobile-optimized content (full height)
  Widget _buildMobileContent(BuildContext context, NoteCreateEditing state) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Container(
      color: colors.themeBgCanvas,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Note name input
          Text(
            appLocalizationsOf(context).noteName,
            style: ArDriveTypographyNew.of(context).heading6(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ArDriveTextFieldNew(
                  key: const Key('note_name_text_field'),
                  controller: _nameController,
                  onChanged: (value) {
                    context.read<NoteCreateCubit>().updateNoteName(value);
                  },
                  hintText: appLocalizationsOf(context).enterNoteName,
                  autofocus: true,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '.md',
                style: ArDriveTypographyNew.of(context)
                    .paragraphNormal()
                    .copyWith(
                      color: colors.themeFgSubtle,
                    ),
              ),
            ],
          ),
          if (state.nameError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _getErrorMessage(context, state.nameError!),
                style: ArDriveTypographyNew.of(context).paragraphSmall(
                      color: colors.themeErrorDefault,
                    ),
              ),
            ),
          const SizedBox(height: 16),

          // Markdown editor - takes remaining space
          Expanded(
            child: NoteEditorWidget(
              initialContent: state.content,
              onChanged: (content) {
                context.read<NoteCreateCubit>().updateContent(content);
              },
              // On mobile, treat split view as edit only (split doesn't fit well on small screens)
              showEditor: state.viewMode == NoteViewMode.editOnly ||
                  state.viewMode == NoteViewMode.splitView,
              showPreview: state.viewMode == NoteViewMode.previewOnly,
              viewMode: state.viewMode == NoteViewMode.splitView
                  ? NoteViewMode.editOnly
                  : state.viewMode,
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
          // Note name input
          Text(
            appLocalizationsOf(context).noteName,
            style: ArDriveTypographyNew.of(context).heading5(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ArDriveTextFieldNew(
                  key: const Key('note_name_text_field'),
                  controller: _nameController,
                  onChanged: (value) {
                    context.read<NoteCreateCubit>().updateNoteName(value);
                  },
                  hintText: appLocalizationsOf(context).enterNoteName,
                  autofocus: true,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '.md',
                style: ArDriveTypographyNew.of(context)
                    .paragraphNormal()
                    .copyWith(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeFgSubtle,
                    ),
              ),
            ],
          ),
          if (state.nameError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _getErrorMessage(context, state.nameError!),
                style: ArDriveTypographyNew.of(context).paragraphSmall(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeErrorDefault,
                    ),
              ),
            ),
          const SizedBox(height: 16),

          // Markdown editor
          SizedBox(
            height: editorHeight,
            child: NoteEditorWidget(
              initialContent: state.content,
              onChanged: (content) {
                context.read<NoteCreateCubit>().updateContent(content);
              },
              showEditor: state.viewMode == NoteViewMode.editOnly ||
                  state.viewMode == NoteViewMode.splitView,
              showPreview: state.viewMode == NoteViewMode.splitView ||
                  state.viewMode == NoteViewMode.previewOnly,
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

  /// Resolves error key to localized error message
  String _getErrorMessage(BuildContext context, NoteNameValidationError errorKey) {
    switch (errorKey) {
      case NoteNameValidationError.empty:
        return appLocalizationsOf(context).noteNameEmptyError;
      case NoteNameValidationError.invalidCharacters:
        return appLocalizationsOf(context).noteNameInvalidCharactersError;
    }
  }

  /// Resolves note creation error key to localized error message
  String _getCreateErrorMessage(BuildContext context, NoteCreateErrorKey errorKey) {
    switch (errorKey) {
      case NoteCreateErrorKey.createFileFailed:
        return appLocalizationsOf(context).noteCreateFileFailed;
    }
  }
}
