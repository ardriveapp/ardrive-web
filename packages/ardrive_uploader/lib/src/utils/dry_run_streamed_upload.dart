import 'dart:async';
import 'dart:math';

import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/streamed_upload.dart';
import 'package:arweave/arweave.dart';

class DryRunStreamedUpload implements StreamedUpload<UploadItem> {
  static const _bytesPerSecond = 1024 * 1024; // 1MB per second
  bool _isCanceled = false;

  @override
  Future<StreamedUploadResult> send(
    UploadItem uploadItem,
    Wallet wallet,
    Function(double)? onProgress,
  ) async {
    if (_isCanceled) {
      return StreamedUploadResult(success: false);
    }

    final totalBytes = uploadItem.size;
    int bytesProcessed = 0;

    while (bytesProcessed < totalBytes) {
      if (_isCanceled) {
        return StreamedUploadResult(success: false);
      }

      // Process 1MB or remaining bytes if less
      final int bytesToProcess = min<int>(
        _bytesPerSecond,
        totalBytes - bytesProcessed,
      );

      bytesProcessed += bytesToProcess;

      // Update progress
      if (onProgress != null) {
        final progress = bytesProcessed / totalBytes;
        onProgress(progress);
      }

      // Wait 1 second before next chunk
      await Future.delayed(const Duration(seconds: 1));
    }

    return StreamedUploadResult(success: true);
  }

  @override
  Future<void> cancel(UploadItem handle) async {
    _isCanceled = true;
  }
}
