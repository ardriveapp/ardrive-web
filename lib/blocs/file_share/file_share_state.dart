part of 'file_share_cubit.dart';

@immutable
abstract class FileShareState extends Equatable {
  const FileShareState();

  @override
  List<Object?> get props => [];
}

/// [FileShareLoadInProgress] means that the file share details are being loaded.
class FileShareLoadInProgress extends FileShareState {}

class FileShareLoadedPendingFile extends FileShareState {}

class FileShareLoadedFailedFile extends FileShareState {}

/// [FileShareLoadSuccess] provides details for the user to share the file with.
class FileShareLoadSuccess extends FileShareState {
  final String fileName;

  /// The link to share access of this file with.
  final Uri fileShareLink;

  /// Whether or not this file is public ie. not encrypted on the network.
  final bool isPublicFile;

  final bool isPending;

  /// The file key, base64url encoded - the *second* artifact of the handover
  /// (`docs/FILE_SHARING_REDESIGN_PLAN.md` decision 4), for the sharer to send
  /// through a different channel than the link.
  ///
  /// `null` for a public file, which has a single artifact and no key at all.
  final String? fileKeyBase64;

  /// Whether the sharer opted into embedding the key in [fileShareLink].
  ///
  /// Off by default: with the key in the link, the link *is* the file.
  final bool keyIsInLink;

  /// Whether the file's name, size and type were left out of the link.
  final bool detailsAreHidden;

  /// Whether the link is pinned to the revision it was built from, rather than
  /// following the file (decision 1: live semantics by default).
  final bool isPinned;

  /// Whether the cipher and IV are still being fetched.
  ///
  /// The link above is already usable while this is `true`; it simply lacks
  /// `c`/`iv`, which costs the recipient one GraphQL request at download time.
  final bool isLoadingCipherDetails;

  const FileShareLoadSuccess({
    required this.fileName,
    required this.fileShareLink,
    required this.isPublicFile,
    required this.isPending,
    this.fileKeyBase64,
    this.keyIsInLink = false,
    this.detailsAreHidden = false,
    this.isPinned = false,
    this.isLoadingCipherDetails = false,
  });

  /// Whether the sharer has a key to hand over separately from the link.
  bool get hasSeparateKeyArtifact => fileKeyBase64 != null && !keyIsInLink;

  @override
  List<Object?> get props => [
        fileName,
        fileShareLink,
        isPublicFile,
        isPending,
        fileKeyBase64,
        keyIsInLink,
        detailsAreHidden,
        isPinned,
        isLoadingCipherDetails,
      ];

  // Equatable stringifies its props in debug builds, and one of them is key
  // material - which would then land in every bloc observer log line.
  @override
  String toString() => 'FileShareLoadSuccess(isPublicFile: $isPublicFile, '
      'isPending: $isPending, keyIsInLink: $keyIsInLink, '
      'detailsAreHidden: $detailsAreHidden, isPinned: $isPinned, '
      'isLoadingCipherDetails: $isLoadingCipherDetails, '
      'fileKey: ${fileKeyBase64 == null ? 'none' : '<redacted>'})';
}
