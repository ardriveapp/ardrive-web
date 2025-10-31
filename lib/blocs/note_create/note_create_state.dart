import 'package:ardrive/blocs/note_create/note_create_cubit.dart';
import 'package:equatable/equatable.dart';

/// Represents the view mode for the markdown editor
enum NoteViewMode {
  /// Show only the markdown editor
  editOnly,

  /// Show both editor and preview side-by-side
  splitView,

  /// Show only the rendered preview
  previewOnly,
}

/// Base state for note creation
abstract class NoteCreateState extends Equatable {
  const NoteCreateState();

  @override
  List<Object?> get props => [];
}

/// Initial state when the note creation dialog is first opened
class NoteCreateInitial extends NoteCreateState {
  const NoteCreateInitial();

  @override
  List<Object?> get props => [];
}

/// State while user is editing the note
class NoteCreateEditing extends NoteCreateState {
  final String noteName;
  final String content;
  final bool isValidName;
  final NoteViewMode viewMode;
  final NoteNameValidationError? nameError;

  const NoteCreateEditing({
    required this.noteName,
    required this.content,
    required this.isValidName,
    this.viewMode = NoteViewMode.splitView,
    this.nameError,
  });

  NoteCreateEditing copyWith({
    String? noteName,
    String? content,
    bool? isValidName,
    NoteViewMode? viewMode,
    NoteNameValidationError? nameError,
    bool clearNameError = false,
  }) {
    return NoteCreateEditing(
      noteName: noteName ?? this.noteName,
      content: content ?? this.content,
      isValidName: isValidName ?? this.isValidName,
      viewMode: viewMode ?? this.viewMode,
      nameError: clearNameError ? null : (nameError ?? this.nameError),
    );
  }

  @override
  List<Object?> get props => [
        noteName,
        content,
        isValidName,
        viewMode,
        nameError,
      ];
}

/// State when an error occurs during note creation
class NoteCreateError extends NoteCreateState {
  final String message;

  const NoteCreateError(this.message);

  @override
  List<Object> get props => [message];
}
