import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/data_bundler.dart';
import 'package:ardrive_uploader/src/utils/logger.dart';
import 'package:arweave/arweave.dart';

class UploadDispatcher {
  UploadFileStrategy _uploadFileStrategy;
  final UploadFolderStructureStrategy _uploadFolderStrategy;
  final DataBundler _dataBundler;

  UploadDispatcher({
    required UploadFileStrategy uploadStrategy,
    required DataBundler dataBundler,
    required UploadFolderStructureStrategy uploadFolderStrategy,
  })  : _dataBundler = dataBundler,
        _uploadFolderStrategy = uploadFolderStrategy,
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
      } else if (task is FolderUploadTask) {
        await _uploadFolderStrategy.upload(
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
