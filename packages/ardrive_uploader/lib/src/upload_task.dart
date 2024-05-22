import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

class FileUploadTask extends UploadTask {
  final IOFile file;

  final ARFSFileUploadMetadata metadata;

  @override
  final UploadItem? uploadItem;

  @override
  final List<ARFSUploadMetadata>? content;

  @override
  final double progress;

  @override
  final String id;

  @override
  bool isProgressAvailable = true;

  bool metadataUploaded;

  @override
  UploadTaskCancelToken? cancelToken;

  @override
  final Object? error;

  @override
  final SecretKey? encryptionKey;

  @override
  UploadType type;

  FileUploadTask({
    this.uploadItem,
    this.isProgressAvailable = true,
    this.status = UploadStatus.notStarted,
    this.content,
    String? id,
    required this.file,
    required this.metadata,
    this.encryptionKey,
    this.cancelToken,
    this.progress = 0,
    required this.type,
    this.metadataUploaded = false,
    this.error,
  }) : id = id ?? const Uuid().v4();

  @override
  UploadStatus status;

  @override
  FileUploadTask copyWith({
    UploadItem? uploadItem,
    double? progress,
    bool? isProgressAvailable,
    UploadStatus? status,
    String? id,
    ARFSFileUploadMetadata? metadata,
    List<ARFSUploadMetadata>? content,
    SecretKey? encryptionKey,
    UploadTaskCancelToken? cancelToken,
    UploadType? type,
    bool? metadataUploaded,
    Object? error,
    IOFile? file,
  }) {
    return FileUploadTask(
      cancelToken: cancelToken ?? this.cancelToken,
      encryptionKey: encryptionKey ?? this.encryptionKey,
      metadata: metadata ?? this.metadata,
      uploadItem: uploadItem ?? this.uploadItem,
      content: content ?? this.content,
      id: id ?? this.id,
      isProgressAvailable: isProgressAvailable ?? this.isProgressAvailable,
      status: status ?? this.status,
      file: file ?? this.file,
      progress: progress ?? this.progress,
      type: type ?? this.type,
      metadataUploaded: metadataUploaded ?? this.metadataUploaded,
      error: error ?? this.error,
    );
  }
}

abstract class UploadTask<T> {
  abstract final String id;
  abstract final UploadItem? uploadItem;
  abstract final List<ARFSUploadMetadata>? content;
  abstract final double progress;
  abstract final bool isProgressAvailable;
  abstract final UploadStatus status;
  abstract final SecretKey? encryptionKey;
  abstract final UploadTaskCancelToken? cancelToken;
  abstract final UploadType type;
  abstract final Object? error;

  String errorInfo() {
    String errorInfo = '';

    errorInfo += 'progress: $progress\n';
    errorInfo += 'status: $status\n';
    errorInfo += 'type: $type\n';
    errorInfo += 'number of content: ${content?.length}\n';
    errorInfo += 'uploadItem: ${uploadItem.toString()}}\n';

    return errorInfo;
  }

  UploadTask copyWith({
    UploadItem? uploadItem,
    double? progress,
    bool? isProgressAvailable,
    UploadStatus? status,
    String? id,
    List<ARFSUploadMetadata>? content,
    SecretKey? encryptionKey,
    UploadTaskCancelToken? cancelToken,
    UploadType? type,
    Object? error,
  });
}

class FolderUploadTask extends UploadTask<ARFSUploadMetadata> {
  final List<(ARFSFolderUploadMetatadata, IOEntity)> folders;

  @override
  final UploadItem? uploadItem;

  @override
  final List<ARFSUploadMetadata>? content;

  @override
  final double progress;

  @override
  final String id;

  @override
  bool isProgressAvailable = true;

  @override
  UploadTaskCancelToken? cancelToken;

  @override
  final UploadType type;

  @override
  final SecretKey? encryptionKey;

  @override
  final Object? error;

  FolderUploadTask({
    required this.folders,
    this.uploadItem,
    this.isProgressAvailable = true,
    this.status = UploadStatus.notStarted,
    this.content,
    this.encryptionKey,
    this.progress = 0,
    this.cancelToken,
    String? id,
    required this.type,
    this.error,
  }) : id = id ?? const Uuid().v4();

  @override
  UploadStatus status;

  @override
  FolderUploadTask copyWith({
    UploadItem? uploadItem,
    double? progress,
    bool? isProgressAvailable,
    UploadStatus? status,
    String? id,
    List<ARFSUploadMetadata>? content,
    SecretKey? encryptionKey,
    List<(ARFSFolderUploadMetatadata, IOEntity)>? folders,
    UploadTaskCancelToken? cancelToken,
    UploadType? type,
    Object? error,
  }) {
    return FolderUploadTask(
      cancelToken: cancelToken ?? this.cancelToken,
      folders: folders ?? this.folders,
      uploadItem: uploadItem ?? this.uploadItem,
      content: content ?? this.content,
      id: id ?? this.id,
      progress: progress ?? this.progress,
      isProgressAvailable: isProgressAvailable ?? this.isProgressAvailable,
      status: status ?? this.status,
      type: type ?? this.type,
      encryptionKey: encryptionKey ?? this.encryptionKey,
      error: error ?? this.error,
    );
  }
}
