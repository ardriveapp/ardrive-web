import 'package:ardrive_uploader/ardrive_uploader.dart';

/// The numbers the progress step shows, counted the way the confirm step
/// counts them: files only, each at its own size.
///
/// The uploader's own totals also count each new folder as an item, and size
/// each file as the data item that carries it, signature and tags included.
/// Shown as they are, the count and sizes grow between the two steps.
class UploadProgressSummary {
  UploadProgressSummary._({
    required this.numberOfFiles,
    required this.numberOfUploadedFiles,
    required this.totalSize,
    required this.totalUploaded,
    required this.progress,
  });

  factory UploadProgressSummary.from(UploadProgress uploadProgress) {
    final tasks = uploadProgress.tasks.values;

    var numberOfFiles = 0;
    var numberOfUploadedFiles = 0;
    var totalSize = 0;
    var totalUploaded = 0;

    for (final task in tasks) {
      final uploaded = isUploaded(task);

      final files = task.content?.whereType<ARFSFileUploadMetadata>() ??
          const <ARFSFileUploadMetadata>[];

      for (final file in files) {
        numberOfFiles++;
        totalSize += file.size;

        if (uploaded) {
          numberOfUploadedFiles++;
        }

        totalUploaded += uploadedBytes(file, task);
      }
    }

    final completeTasks = tasks.where(isUploaded).length;
    final allComplete = tasks.isNotEmpty && completeTasks == tasks.length;

    final double progress;

    if (allComplete) {
      progress = 1;
    } else {
      // Bytes can all be sent while the last file is still finalizing, so the
      // total stays below 100% until every task is complete.
      final sent = totalSize > 0
          ? totalUploaded / totalSize
          : tasks.isEmpty
              ? 0.0
              : completeTasks / tasks.length;
      progress = sent.clamp(0.0, 0.99);
    }

    return UploadProgressSummary._(
      numberOfFiles: numberOfFiles,
      numberOfUploadedFiles: numberOfUploadedFiles,
      totalSize: totalSize,
      totalUploaded: totalUploaded,
      progress: progress,
    );
  }

  /// Whether [task]'s data is all sent. A file being given its ArNS name has
  /// already uploaded.
  static bool isUploaded(UploadTask task) =>
      task.status == UploadStatus.complete ||
      task.status == UploadStatus.assigningUndername;

  /// How much of [file] is sent, at the file's own size.
  static int uploadedBytes(ARFSFileUploadMetadata file, UploadTask task) {
    if (isUploaded(task)) {
      return file.size;
    }

    return (file.size * task.progress.clamp(0.0, 1.0)).ceil();
  }

  final int numberOfFiles;
  final int numberOfUploadedFiles;

  /// The files' own sizes, in bytes.
  final int totalSize;
  final int totalUploaded;

  /// From 0 to 1. It is 1 only when every task's data is sent.
  final double progress;

  /// [progress] as a whole percentage, rounded down.
  int get percent => (progress * 100).floor();
}
