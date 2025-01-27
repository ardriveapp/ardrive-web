/// A repository for handling file metadata operations.
abstract class FileMetadataRepository {
  /// Fetches metadata for multiple files from Arweave using their transaction IDs.
  ///
  /// Returns a [FileMetadataResult] containing the metadata for each file.
  /// If a file's metadata cannot be fetched, it will be included in the failures list.
  Future<FileMetadataResult> getFileMetadata(List<String> fileIds);
}

/// The result of a file metadata fetch operation.
class FileMetadataResult {
  final Map<String, FileMetadata> metadata;
  final List<FileMetadataFailure> failures;

  FileMetadataResult({
    required this.metadata,
    required this.failures,
  });
}

/// Represents the metadata for a file.
class FileMetadata {
  final String id;
  final String name;
  final String dataTxId;
  final String contentType;
  final int size;
  final DateTime lastModifiedDate;
  final Map<String, dynamic> customMetadata;

  FileMetadata({
    required this.id,
    required this.name,
    required this.dataTxId,
    required this.contentType,
    required this.size,
    required this.lastModifiedDate,
    this.customMetadata = const {},
  });

  factory FileMetadata.fromJson(Map<String, dynamic> json) {
    return FileMetadata(
      id: json['id'] as String,
      name: json['name'] as String,
      dataTxId: json['dataTxId'] as String,
      contentType: json['contentType'] as String,
      size: json['size'] as int,
      lastModifiedDate: DateTime.parse(json['lastModifiedDate'] as String),
      customMetadata: json['customMetadata'] as Map<String, dynamic>? ?? {},
    );
  }
}

/// Represents a failure to fetch file metadata.
class FileMetadataFailure {
  final String fileId;
  final String error;

  FileMetadataFailure({
    required this.fileId,
    required this.error,
  });
}
