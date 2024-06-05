import 'dart:async';

import 'package:ardrive_io/ardrive_io.dart';
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
  final DataBundler _dataBundler;

  UploadDispatcher({
    required UploadFileStrategy uploadStrategy,
    required DataBundler dataBundler,
    required UploadFolderStructureStrategy uploadFolderStrategy,
    required UploadThumbnailStrategy uploadThumbnailStrategy,
  })  : _dataBundler = dataBundler,
        _uploadFolderStrategy = uploadFolderStrategy,
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
        final dataItems = await _dataBundler.createDataItemsForFile(
          file: task.file,
          metadata: task.metadata,
          wallet: wallet,
          driveKey: task.encryptionKey,
          onStartBundleCreation: () {
            controller.updateProgress(
              task: task.copyWith(
                status: UploadStatus.creatingBundle,
              ),
            );
          },
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
          dataItems: dataItems,
          task: task,
          wallet: wallet,
          controller: controller,
          verifyCancel: verifyCancel,
        );

        var updatedTask = controller.tasks[task.id]!;

        if (task.file.contentType == 'image/jpeg') {
          controller.updateProgress(
            task: updatedTask.copyWith(
              status: UploadStatus.uploadingThumbnail,
            ),
          );

          final data = generateThumbnail(await task.file.readAsBytes());

          final thumbnailMetadata = ThumbnailUploadMetadata(
            thumbnailSize: 0,
            relatesTo:
                (task.content!.first as ARFSFileUploadMetadata).dataTxId!,
            entityMetadataTags: [],
          );

          final thumb = await IOFileAdapter().fromData(
            data,
            name: 'thumbnail',
            lastModifiedDate: DateTime.now(),
            contentType: 'image/jpeg',
          );

          final dataItem = await _dataBundler.createDataItemForThumbnail(
              file: thumb, metadata: thumbnailMetadata, wallet: wallet);

          final thumbnailTask = ThumbnailUploadTask(
            file: thumb,
            metadata: thumbnailMetadata,
            type: task.type,
            uploadItem: DataItemUploadItem(
              size: dataItem.dataItemSize,
              data: dataItem,
            ),
            id: Uuid().v4(),
          );

          await _uploadThumbnailStrategy.upload(
            task: thumbnailTask,
            wallet: wallet,
            controller: UploadController(StreamController(), this),
            verifyCancel: verifyCancel,
          );

          updatedTask = controller.tasks[task.id]!;

          final uploadContent = task.content!.first as ARFSFileUploadMetadata;

          uploadContent.updateThumbnailTxId(
              (thumbnailTask.uploadItem as DataItemUploadItem).data.id);

          controller.updateProgress(
            task: updatedTask.copyWith(
                status: UploadStatus.complete, content: [uploadContent]),
          );
        }
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
