import 'dart:async';

import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/constants.dart';
import 'package:ardrive_uploader/src/data_bundler.dart';
import 'package:ardrive_uploader/src/exceptions.dart';
import 'package:ardrive_uploader/src/utils/data_bundler_utils.dart';
import 'package:ardrive_uploader/src/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';

abstract class UploadFileStrategy {
  Future<void> upload({
    required List<DataItemFile> dataItems,
    required FileUploadTask task,
    required Wallet wallet,
    required UploadController controller,
    required bool Function() verifyCancel,
  });
}

abstract class UploadThumbnailStrategy {
  Future<void> upload({
    required ThumbnailUploadTask task,
    required Wallet wallet,
    required UploadController controller,
    required bool Function() verifyCancel,
  });

  factory UploadThumbnailStrategy({
    required StreamedUploadFactory streamedUploadFactory,
    required DataBundler dataBundler,
  }) {
    return _UploadThumbnailStrategy(
      streamedUploadFactory: streamedUploadFactory,
      dataBundler: dataBundler,
    );
  }
}

abstract class UploadFolderStructureStrategy {
  Future<void> upload({
    required FolderUploadTask task,
    required Wallet wallet,
    required UploadController controller,
    required bool Function() verifyCancel,
  });
}

class UploadFileUsingDataItemFiles extends UploadFileStrategy {
  final StreamedUploadFactory _streamedUploadFactory;

  UploadFileUsingDataItemFiles({
    required StreamedUploadFactory streamedUploadFactory,
  }) : _streamedUploadFactory = streamedUploadFactory;

  @override
  Future<void> upload({
    required List<DataItemFile> dataItems,
    required FileUploadTask task,
    required Wallet wallet,
    required UploadController controller,
    required bool Function() verifyCancel,
  }) async {
    final dataItemResults = await createDataItemResultFromDataItemFiles(
      dataItems,
      wallet,
    );

    logger.i('metadata uploaded for the file: ${task.metadataUploaded}');

    /// uploads the metadata item if it hasn't been uploaded yet. It can happen
    /// that the metadata item is uploaded but the data item is not, so we need
    /// to check for that.
    if (!task.metadataUploaded) {
      logger.i('uploading metadata for the file');

      final metadataItem = dataItemResults[0];

      /// The upload can be canceled while the bundle is being created
      if (verifyCancel()) {
        logger.w('Upload canceled while data item was being created');
        throw UploadCanceledException(
          'Upload canceled while metadata item was being created',
        );
      }

      final metadataStreamedUpload =
          await _streamedUploadFactory.fromUploadType(task);

      final headersMap = <String, String>{
        'x-paid-by': dataItems[0].paidBy.join(', '),
      };

      final uploadResult = await metadataStreamedUpload.send(
          DataItemUploadItem(
            size: metadataItem.dataItemSize,
            data: metadataItem,
            headers: headersMap,
          ),
          wallet, (progress) {
        // we don't need to update the progress of the metadata item
      });

      logger.i('metadata upload result: $uploadResult');

      if (!uploadResult.success) {
        throw MetadataTransactionUploadException(
          message: 'Failed to upload metadata item. DataItem won\'t be sent.',
          error: uploadResult.error,
        );
      }

      task.metadataUploaded = true;
      controller.updateProgress(task: task);
    }

    final dataItem = dataItemResults[1];

    await _sendDataItem(
      controller: controller,
      dataItem: dataItem,
      task: task,
      verifyCancel: verifyCancel,
      wallet: wallet,
    );
  }

  Future<void> _sendDataItem({
    required FileUploadTask task,
    required DataItemResult dataItem,
    required UploadController controller,
    required bool Function() verifyCancel,
    required Wallet wallet,
  }) async {
    /// sends the data item
    var dataItemTask = task.copyWith(
      uploadItem: DataItemUploadItem(
          size: dataItem.dataItemSize,
          data: dataItem,
          headers: <String, String>{
            'x-paid-by': task.metadata.paidBy.join(', '),
          }),
    );

    controller.updateProgress(
      task: task.copyWith(
        uploadItem: DataItemUploadItem(
          size: dataItem.dataItemSize,
          data: dataItem,
          headers: <String, String>{
            'x-paid-by': task.metadata.paidBy.join(', '),
          },
        ),
      ),
    );

    /// The upload can be canceled while the bundle is being created
    if (verifyCancel()) {
      logger.w('Upload canceled while data item was being created');
      throw UploadCanceledException(
        'Upload canceled while data data item was being created',
      );
    }

    final streamedUpload = await _streamedUploadFactory.fromUploadType(task);

    dataItemTask = dataItemTask.copyWith(
      status: UploadStatus.inProgress,
      cancelToken: UploadTaskCancelToken(
        cancel: () => streamedUpload.cancel(dataItemTask.uploadItem!),
      ),
    );

    /// adds the cancel token to the task
    controller.updateProgress(task: dataItemTask);

    final result = await streamedUpload.send(
      dataItemTask.uploadItem!,
      wallet,
      (progress) {
        controller.updateProgress(
          task: dataItemTask.copyWith(
            progress: progress,
          ),
        );
      },
    );

    if (!result.success) {
      throw DataTransactionUploadException(
        message:
            'Failed to upload data item. It will cause a creation of a ghost file e.g. a file with a red dot.',
        error: result.error,
      );
    }
  }
}

class UploadFileUsingBundleStrategy extends UploadFileStrategy {
  final DataBundler _dataBundler;
  final StreamedUploadFactory _streamedUploadFactory;

  UploadFileUsingBundleStrategy({
    required DataBundler dataBundler,
    required StreamedUploadFactory streamedUploadFactory,
  })  : _dataBundler = dataBundler,
        _streamedUploadFactory = streamedUploadFactory;

  @override
  Future<void> upload({
    required List<DataItemFile> dataItems,
    required FileUploadTask task,
    required Wallet wallet,
    required UploadController controller,
    required bool Function() verifyCancel,
  }) async {
    final bundle = await _dataBundler.createDataBundle(
      file: task.file,
      dataItemFiles: dataItems,
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
      customBundleTags: customBundleTags(task.type),
      onStartMetadataCreation: () {
        controller.updateProgress(
          task: task.copyWith(
            status: UploadStatus.creatingMetadata,
          ),
        );
      },
    );

    if (bundle is TransactionResult) {
      task = task.copyWith(
        uploadItem: TransactionUploadItem(
          size: bundle.dataSize,
          data: bundle,
        ),
      );
      controller.updateProgress(
        task: task,
      );
    } else if (bundle is DataItemResult) {
      task = task.copyWith(
        uploadItem: DataItemUploadItem(
          size: bundle.dataItemSize,
          data: bundle,
          headers: <String, String>{
            'x-paid-by': task.metadata.paidBy.join(', '),
          },
        ),
      );

      controller.updateProgress(
        task: task,
      );
    } else {
      throw Exception('Unknown bundle type');
    }

    /// The upload can be canceled while the bundle is being created
    if (verifyCancel()) {
      logger.w('Upload canceled while bundle was being created');
      throw UploadCanceledException('Upload canceled');
    }

    final streamedUpload = await _streamedUploadFactory.fromUploadType(task);

    task = task.copyWith(
      status: UploadStatus.inProgress,
      cancelToken: UploadTaskCancelToken(
        cancel: () => streamedUpload.cancel(task.uploadItem!),
      ),
    );

    controller.updateProgress(task: task);

    final result =
        await streamedUpload.send(task.uploadItem!, wallet, (progress) {
      controller.updateProgress(
        task: task.copyWith(
          progress: progress,
        ),
      );
    });

    if (!result.success) {
      throw BundleUploadException(
        message: 'Failed to upload file bundle. Bundle: $bundle',
        error: result.error,
      );
    }

    controller.updateProgress(
      task: task.copyWith(
        status: UploadStatus.complete,
      ),
    );
  }
}

class UploadFolderStructureAsBundleStrategy
    extends UploadFolderStructureStrategy {
  final DataBundler _dataBundler;
  final StreamedUploadFactory _streamedUploadFactory;

  UploadFolderStructureAsBundleStrategy({
    required DataBundler dataBundler,
    required StreamedUploadFactory streamedUploadFactory,
  })  : _dataBundler = dataBundler,
        _streamedUploadFactory = streamedUploadFactory;

  @override
  Future<void> upload({
    required FolderUploadTask task,
    required Wallet wallet,
    required UploadController controller,
    required bool Function() verifyCancel,
  }) async {
    // creates the bundle for folders
    final bundle = await _dataBundler.createDataBundleForEntities(
      entities: task.folders,
      wallet: wallet,
      driveKey: task.encryptionKey,
      customBundleTags: customBundleTags(task.type),
    );

    final folderBundle = (bundle).first.dataItemResult;

    FolderUploadTask folderTask = task;

    if (folderBundle is TransactionResult) {
      folderTask = folderTask.copyWith(
        uploadItem: TransactionUploadItem(
          size: folderBundle.dataSize,
          data: folderBundle,
        ),
      );

      controller.updateProgress(task: folderTask);
    } else if (folderBundle is DataItemResult) {
      folderTask = folderTask.copyWith(
        uploadItem: DataItemUploadItem(
          size: folderBundle.dataSize,
          data: folderBundle,
          headers: <String, String>{
            'x-paid-by': task.folders.first.$1.paidBy.join(', '),
          },
        ),
      );
      controller.updateProgress(task: folderTask);
    } else {
      throw Exception('Unknown bundle type');
    }

    if (verifyCancel()) {
      logger.w('Upload canceled after bundle creation and before upload');
      throw UploadCanceledException('Upload canceled on bundle creation');
    }

    final streamedUpload =
        await _streamedUploadFactory.fromUploadType(folderTask);

    final result =
        await streamedUpload.send(folderTask.uploadItem!, wallet, (progress) {
      folderTask = folderTask.copyWith(
        progress: progress,
      );
      controller.updateProgress(task: folderTask);
    });

    if (!result.success) {
      throw BundleUploadException(
        message: 'Failed to upload bundle of folders. Folder bundle: $bundle',
        error: result.error,
      );
    }

    controller.updateProgress(
      task: folderTask.copyWith(
        status: UploadStatus.complete,
      ),
    );
  }
}

class _UploadThumbnailStrategy implements UploadThumbnailStrategy {
  final StreamedUploadFactory _streamedUploadFactory;

  _UploadThumbnailStrategy({
    required StreamedUploadFactory streamedUploadFactory,
    required DataBundler dataBundler,
  }) : _streamedUploadFactory = streamedUploadFactory;

  @override
  Future<void> upload({
    required ThumbnailUploadTask task,
    required Wallet wallet,
    required UploadController controller,
    required bool Function() verifyCancel,
  }) async {
    if (task.uploadItem == null) {
      final thumbnailDataItem = await createDataItemForThumbnail(
        file: task.file,
        metadata: task.metadata,
        wallet: wallet,
        encryptionKey: task.encryptionKey,
        fileId: task.metadata.originalFileId,
      );

      task = task.copyWith(
          uploadItem: DataItemUploadItem(
        size: thumbnailDataItem.dataItemSize,
        data: thumbnailDataItem,
        headers: <String, String>{
          'x-paid-by': task.metadata.paidBy.join(', '),
        },
      ));
    }

    /// It will always use the Turbo for now

    final streamedUpload = await _streamedUploadFactory.fromUploadType(task);

    final result = await streamedUpload.send(
      task.uploadItem!,
      wallet,
      (progress) {
        controller.updateProgress(
          task: task.copyWith(
            progress: progress,
          ),
        );
      },
    );

    if (!result.success) {
      throw ThumbnailUploadException(
        message: 'Failed to upload thumbnail',
        error: result.error,
      );
    }

    controller.updateProgress(
      task: task.copyWith(
        status: UploadStatus.complete,
      ),
    );
  }
}

List<Tag>? customBundleTags(
  UploadType type,
) {
  if (type == UploadType.d2n) {
    return _uTags;
  } else {
    return null;
  }
}

List<Tag> get _uTags {
  return [
    Tag(EntityTag.appName, 'SmartWeaveAction'),
    Tag(EntityTag.appVersion, '0.3.0'),
    Tag(EntityTag.input, '{"function":"mint"}'),
    Tag(EntityTag.contract, uContractId.toString()),
  ];
}
