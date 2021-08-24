part of 'file_share_cubit.dart';

@immutable
abstract class FileShareState extends Equatable {
  const FileShareState();

  @override
  List<Object> get props => [];
}

/// [FileShareLoadInProgress] means that the file share details are being loaded.
class FileShareLoadInProgress extends FileShareState {}

/// [FileShareLoadSuccess] provides details for the user to share the file with.
class FileShareLoadSuccess extends FileShareState {
  final String fileName;

  /// The link to share access of this file with.
  final Uri fileShareLink;

  /// Whether or not this file is public ie. not encrypted on the network.
  final bool isPublicFile;

  FileShareLoadSuccess({
    required this.fileName,
    required this.fileShareLink,
    required this.isPublicFile,
  });

  @override
  List<Object> get props => [fileName, fileShareLink, isPublicFile];
}
