part of 'shared_file_cubit.dart';

@immutable
abstract class SharedFileState extends Equatable {
  const SharedFileState();

  @override
  List<Object?> get props => [];
}

class SharedFileLoadInProgress extends SharedFileState {}

/// [SharedFileIsPrivate] indicates that the shared file is encrypted and that a
/// file key is needed before anything about it can be shown.
class SharedFileIsPrivate extends SharedFileState {}

/// [SharedFileLoadSuccess] indicates that the shared file being viewed has been
/// loaded successfully.
class SharedFileLoadSuccess extends SharedFileState {
  final List<FileRevision> fileRevisions;
  final SecretKey? fileKey;
  final LicenseState? latestLicense;
  final String? ownerAddress;

  const SharedFileLoadSuccess({
    required this.fileRevisions,
    this.fileKey,
    this.latestLicense,
    this.ownerAddress,
  });

  @override
  List<Object?> get props => [fileRevisions, fileKey, ownerAddress];
}

/// [SharedFileKeyInvalid] indicates that a file key was provided - either typed
/// by the user or read from the link - but that it could not decrypt the file's
/// metadata.
///
/// The file itself is known to exist, so this must never be reported as a
/// missing file. The key entry gate stays on screen with an inline error so
/// that another key can be tried.
class SharedFileKeyInvalid extends SharedFileState {
  /// Whether the key never made it out of the link intact, as opposed to a key
  /// that was decoded and then failed to decrypt the file.
  ///
  /// A damaged key means the link itself arrived mangled - truncated by a mail
  /// client, cut short by a chat app - so the recipient is told to ask for the
  /// link again rather than to re-check a key they never really had.
  final bool linkKeyIsDamaged;

  const SharedFileKeyInvalid({this.linkKeyIsDamaged = false});

  @override
  List<Object?> get props => [linkKeyIsDamaged];
}

/// [SharedFileNotFound] indicates that no file with the shared file id could be
/// found on the network.
class SharedFileNotFound extends SharedFileState {}

/// [SharedFileLoadFailure] indicates that the shared file could not be loaded
/// because of an unexpected failure, typically a network or gateway error.
///
/// The load can be run again with [SharedFileCubit.retry].
class SharedFileLoadFailure extends SharedFileState {}
