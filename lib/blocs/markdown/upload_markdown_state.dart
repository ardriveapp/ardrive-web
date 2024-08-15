import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

@immutable
abstract class UploadMarkdownState extends Equatable {
  @override
  List get props => [];
}

/// Initial state where user begins by selecting a name for the markdown file
class UploadMarkdownInitial extends UploadMarkdownState {
  final String markdownFilename;
  final FolderEntry parentFolderEntry;

  UploadMarkdownInitial(
      {required this.markdownFilename, required this.parentFolderEntry});
}

/// User has selected a folder and we are checking for name conflicts
class UploadMarkdownCheckingForConflicts extends UploadMarkdownState {
  final FolderEntry parentFolderEntry;

  UploadMarkdownCheckingForConflicts({required this.parentFolderEntry});

  @override
  List<Object> get props => [parentFolderEntry];
}

/// There is an existing non-markdown FILE or FOLDER entity with a
/// conflicting name. User must re-name the markdown or abort the action
class UploadMarkdownNameConflict extends UploadMarkdownState {
  final String conflictingName;
  final FolderEntry parentFolderEntry;

  UploadMarkdownNameConflict({
    required this.conflictingName,
    required this.parentFolderEntry,
  });

  @override
  List<Object> get props => [conflictingName, parentFolderEntry];
}

/// There is an existing markdown file with a conflicting name. Prompt the
/// user to confirm that this is a revision upload or abort the action
class UploadMarkdownRevisionConfirm extends UploadMarkdownState {
  final FileID existingMarkdownFileId;
  final FolderEntry parentFolderEntry;

  UploadMarkdownRevisionConfirm({
    required this.existingMarkdownFileId,
    required this.parentFolderEntry,
  });

  @override
  List<Object> get props => [existingMarkdownFileId, parentFolderEntry];
}

/// Conflicts have been resolved and we will now prepare the markdown file transaction
class UploadMarkdownPreparingFile extends UploadMarkdownState {
  final FolderEntry parentFolderEntry;

  UploadMarkdownPreparingFile({required this.parentFolderEntry});

  @override
  List<Object> get props => [parentFolderEntry];
}

class MarkdownUploadReview extends UploadMarkdownState {
  final int markdownSize;
  final String markdownName;
  final IOFile markdownFile;
  final bool freeUpload;
  final UploadMethod? uploadMethod;
  final Drive drive;
  final FolderEntry parentFolderEntry;
  final String? existingMarkdownFileId;
  final bool canUpload;

  MarkdownUploadReview({
    required this.markdownSize,
    required this.markdownName,
    required this.markdownFile,
    this.freeUpload = false,
    this.uploadMethod,
    required this.drive,
    required this.parentFolderEntry,
    this.existingMarkdownFileId,
    this.canUpload = false,
  });

  @override
  List get props => [
        markdownSize,
        markdownName,
        markdownFile,
        freeUpload,
        uploadMethod,
        drive,
        parentFolderEntry,
        existingMarkdownFileId,
      ];

  MarkdownUploadReview copyWith({
    int? markdownSize,
    String? markdownName,
    bool? folderHasPendingFiles,
    IOFile? markdownFile,
    bool? freeUpload,
    UploadMethod? uploadMethod,
    Drive? drive,
    FolderEntry? parentFolderEntry,
    String? existingMarkdownFileId,
    bool? canUpload,
  }) {
    return MarkdownUploadReview(
      markdownSize: markdownSize ?? this.markdownSize,
      markdownName: markdownName ?? this.markdownName,
      markdownFile: markdownFile ?? this.markdownFile,
      freeUpload: freeUpload ?? this.freeUpload,
      uploadMethod: uploadMethod ?? this.uploadMethod,
      drive: drive ?? this.drive,
      parentFolderEntry: parentFolderEntry ?? this.parentFolderEntry,
      existingMarkdownFileId:
          existingMarkdownFileId ?? this.existingMarkdownFileId,
      canUpload: canUpload ?? this.canUpload,
    );
  }
}

/// User has confirmed the upload and the markdown transaction upload has started
class MarkdownUploadInProgress extends UploadMarkdownState {}

/// Private drive has been detected, create markdown must be aborted
class UploadMarkdownPrivacyMismatch extends UploadMarkdownState {}

/// Provided wallet does not match the expected wallet, create markdown must be aborted
class UploadMarkdownWalletMismatch extends UploadMarkdownState {}

/// Markdown transaction upload has failed
class UploadMarkdownFailure extends UploadMarkdownState {}

/// Markdown transaction has been successfully uploaded
class UploadMarkdownSuccess extends UploadMarkdownState {}
