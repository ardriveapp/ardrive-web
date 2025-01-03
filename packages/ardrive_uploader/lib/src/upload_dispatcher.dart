import 'dart:async';

import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/data_bundler.dart';
import 'package:ardrive_uploader/src/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:uuid/uuid.dart';

class UploadDispatcher {
  UploadFileStrategy _uploadFileStrategy;
  final UploadFolderStructureStrategy _uploadFolderStrategy;
  final UploadThumbnailStrategy _uploadThumbnailStrategy;

  UploadDispatcher({
    required UploadFileStrategy uploadStrategy,
    required DataBundler dataBundler,
    required UploadFolderStructureStrategy uploadFolderStrategy,
    required UploadThumbnailStrategy uploadThumbnailStrategy,
  })  : _uploadFolderStrategy = uploadFolderStrategy,
        _uploadThumbnailStrategy = uploadThumbnailStrategy,
        _uploadFileStrategy = uploadStrategy;

  Future<UploadResult> send({
    required UploadTask task,
    required Wallet wallet,
    required UploadController controller,
    required bool Function() verifyCancel,
  }) async {
    try {
      if (task is FileUploadTask) {
        logger.d('Preparing data items for file ${task.file.name}...');

        controller.updateProgress(
          task: task.copyWith(
            status: UploadStatus.creatingMetadata,
          ),
        );

        final uploadPreparation = await prepareDataItems(
          file: task.file,
          metadata: task.metadata,
          wallet: wallet,
          addThumbnail: task.uploadThumbnail,
          driveKey: task.encryptionKey,
          onStartMetadataCreation: () {
            controller.updateProgress(
              task: task.copyWith(
                status: UploadStatus.creatingMetadata,
              ),
            );
          },
        );

        logger.d(
            'Uploading task ${task.id} with strategy: ${_uploadFileStrategy.runtimeType}');

        await _uploadFileStrategy.upload(
          dataItems: uploadPreparation.dataItemFiles,
          task: task,
          wallet: wallet,
          controller: controller,
          verifyCancel: verifyCancel,
        );

        var updatedTask = controller.tasks[task.id]! as FileUploadTask;

        /// Verify supported extentions
        if (FileTypeHelper.isImage(updatedTask.metadata.dataContentType) &&
            task.uploadThumbnail) {
          try {
            controller.updateProgress(
              task: updatedTask.copyWith(
                status: UploadStatus.uploadingThumbnail,
              ),
            );

            final fileMetadata = updatedTask.metadata;

            final thumbnailMetadata = fileMetadata.thumbnailInfo?.first;

            final thumbnailTask = ThumbnailUploadTask(
              file: uploadPreparation.thumbnailFile!,
              metadata: thumbnailMetadata!,
              type: task.type,
              uploadItem: DataItemUploadItem(
                  size: uploadPreparation.thumbnailDataItem!.dataSize,
                  data: uploadPreparation.thumbnailDataItem!),
              id: Uuid().v4(),

              /// same encryption key as the file
              encryptionKey: task.encryptionKey,
            );

            await _uploadThumbnailStrategy.upload(
              task: thumbnailTask,
              wallet: wallet,
              controller: UploadController(StreamController(), this),
              verifyCancel: verifyCancel,
            );
          } catch (e) {
            logger.e(
              'Error uploading thumbnail. The file upload wont be affected.',
              e,
            );
          }
        }

        updatedTask = controller.tasks[task.id]! as FileUploadTask;

        controller.updateProgress(
          task: updatedTask.copyWith(
              status: UploadStatus.complete, content: [updatedTask.metadata]),
        );
      } else if (task is FolderUploadTask) {
        await _uploadFolderStrategy.upload(
          task: task,
          wallet: wallet,
          controller: controller,
          verifyCancel: verifyCancel,
        );
      } else if (task is ThumbnailUploadTask) {
        await _uploadThumbnailStrategy.upload(
          task: task,
          wallet: wallet,
          controller: controller,
          verifyCancel: verifyCancel,
        );
      } else {
        throw Exception('Invalid task type');
      }

      return UploadResult(success: true);
    } catch (e, stacktrace) {
      logger.d('Error on UploadDispatcher.send: $e $stacktrace');
      return UploadResult(
        success: false,
        error: e,
      );
    }
  }

  void setUploadFileStrategy(UploadFileStrategy strategy) {
    _uploadFileStrategy = strategy;
  }
}
