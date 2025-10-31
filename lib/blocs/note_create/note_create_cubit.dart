import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'note_create_state.dart';

/// Error keys for note name validation
enum NoteNameValidationError {
  empty,
  invalidCharacters,
}

/// Error keys for note creation failures
enum NoteCreateErrorKey {
  createFileFailed,
}

/// Cubit for managing note creation state
class NoteCreateCubit extends Cubit<NoteCreateState> {
  final String driveId;
  final String parentFolderId;

  NoteCreateCubit({
    required this.driveId,
    required this.parentFolderId,
  }) : super(const NoteCreateInitial()) {
    // Initialize with empty editing state
    emit(const NoteCreateEditing(
      noteName: '',
      content: '',
      isValidName: false,
      viewMode: NoteViewMode.splitView,
    ));
  }

  /// Updates the note name and validates it
  void updateNoteName(String name) {
    final currentState = state;
    if (currentState is! NoteCreateEditing) return;

    final validation = _validateNoteName(name);

    emit(currentState.copyWith(
      noteName: name,
      isValidName: validation.isValid,
      nameError: validation.errorKey,
      clearNameError: validation.isValid, // Clear error when valid
    ));
  }

  /// Updates the markdown content
  void updateContent(String content) {
    final currentState = state;
    if (currentState is! NoteCreateEditing) return;

    emit(currentState.copyWith(content: content));
  }

  /// Sets the view mode (edit, split, or preview)
  void setViewMode(NoteViewMode mode) {
    final currentState = state;
    if (currentState is! NoteCreateEditing) return;

    emit(currentState.copyWith(viewMode: mode));
  }

  /// Cycles through view modes: edit -> split -> preview -> edit
  void cycleViewMode() {
    final currentState = state;
    if (currentState is! NoteCreateEditing) return;

    final nextMode = switch (currentState.viewMode) {
      NoteViewMode.editOnly => NoteViewMode.splitView,
      NoteViewMode.splitView => NoteViewMode.previewOnly,
      NoteViewMode.previewOnly => NoteViewMode.editOnly,
    };

    emit(currentState.copyWith(viewMode: nextMode));
  }

  /// Creates an IOFile from the current note content
  /// Returns null if the note name is invalid
  Future<IOFile?> createNoteFile() async {
    final currentState = state;
    if (currentState is! NoteCreateEditing) return null;
    if (!currentState.isValidName) return null;

    // Save the editing state to restore after error
    final editingState = currentState;

    try {
      // Convert markdown content to bytes
      final bytes = utf8.encode(currentState.content);

      // Trim the note name and create IOFile with .md extension
      final trimmedName = currentState.noteName.trim();
      final fileName = trimmedName.endsWith('.md')
          ? trimmedName
          : '$trimmedName.md';

      final ioFile = await IOFile.fromData(
        Uint8List.fromList(bytes),
        name: fileName,
        lastModifiedDate: DateTime.now(),
        contentType: 'text/markdown',
      );

      return ioFile;
    } catch (e) {
      // Log the error internally
      logger.e('Failed to create note file', e);
      // Emit error state temporarily to show error to user
      emit(const NoteCreateError(NoteCreateErrorKey.createFileFailed));
      // Restore editing state to keep UI interactive
      emit(editingState);
      return null;
    }
  }

  /// Validates the note name
  _ValidationResult _validateNoteName(String name) {
    // Trim the name for validation to allow typing with trailing spaces
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      return const _ValidationResult(
        isValid: false,
        errorKey: NoteNameValidationError.empty,
      );
    }

    // Remove .md extension if present for validation
    final nameWithoutExtension = trimmedName.endsWith('.md')
        ? trimmedName.substring(0, trimmedName.length - 3)
        : trimmedName;

    // Use same validation as file names
    final fileNameRegex = RegExp(r'^[^\/\\\*]+$');

    if (!fileNameRegex.hasMatch(nameWithoutExtension)) {
      return const _ValidationResult(
        isValid: false,
        errorKey: NoteNameValidationError.invalidCharacters,
      );
    }

    return const _ValidationResult(isValid: true);
  }
}

/// Internal validation result class
class _ValidationResult {
  final bool isValid;
  final NoteNameValidationError? errorKey;

  const _ValidationResult({required this.isValid, this.errorKey});
}
