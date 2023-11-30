import 'dart:async';

import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/data_bundler.dart';
import 'package:ardrive_uploader/src/factories.dart';
import 'package:ardrive_uploader/src/utils/data_bundler_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/foundation.dart';

abstract class UploadFileStrategy {
  Future<void> uploadFile({
    required List<DataItemFile> dataItems,
    required FileUploadTask task,
    required Wallet wallet,
    required UploadController controller,
    required bool Function() verifyCancel,
  });
}

abstract class UploadFolderStructureStrategy {
  Future<void> uploadFolder({
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
  Future<void> uploadFile({
    required List<DataItemFile> dataItems,
    required FileUploadTask task,
    required Wallet wallet,
    required UploadController controller,
    required bool Function() verifyCancel,
  }) async {
    /// sends the metadata item first
    final dataItemResults = await createDataItemResultFromDataItemFiles(
      dataItems,
      wallet,
    );

    final metadataItem = dataItemResults[0];

    final dataItem = dataItemResults[1];

    /// The upload can be canceled while the bundle is being created
    if (verifyCancel()) {
      debugPrint('Upload canceled while data item was being created');
      throw Exception('Upload canceled while metadata item was being created');
    }

    final metadataStreamedUpload =
        _streamedUploadFactory.fromUploadType(task.type);

    final uploadResult = await metadataStreamedUpload.send(
        DataItemUploadItem(
          size: metadataItem.dataItemSize,
          data: metadataItem,
        ),
        wallet, (progress) {
      // we don't need to update the progress of the metadata item
    });

    if (!uploadResult.success) {
      throw Exception(
          'Failed to upload metadata item. DataItem won\'t be sent');
    }

    /// sends the data item
    var dataItemTask = task.copyWith(
      uploadItem: DataItemUploadItem(
        size: dataItem.dataItemSize,
        data: dataItem,
      ),
    );

    controller.updateProgress(
      task: task.copyWith(
        uploadItem: DataItemUploadItem(
          size: dataItem.dataItemSize,
          data: dataItem,
        ),
      ),
    );

    /// The upload can be canceled while the bundle is being created
    if (verifyCancel()) {
      debugPrint('Upload canceled while data item was being created');
      throw Exception('Upload canceled while data data item was being created');
    }

    final streamedUpload = _streamedUploadFactory.fromUploadType(task.type);

    // TODO: review this. Should implement a new API for adding the token.

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
      debugPrint('Failed to upload data item');
      throw Exception('Failed to upload data item');
    }

    final updatedTask = controller.tasks[task.id]!;

    controller.updateProgress(
      task: updatedTask.copyWith(
        status: UploadStatus.complete,
      ),
    );
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
  Future<void> uploadFile({
    required List<DataItemFile> dataItems,
    required FileUploadTask task,
    required Wallet wallet,
    required UploadController controller,
    required bool Function() verifyCancel,
  }) async {
    final bundle = await _dataBundler.createDataBundle(
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

    if (bundle is TransactionResult) {
      controller.updateProgress(
        task: task.copyWith(
          uploadItem: TransactionUploadItem(
            size: bundle.dataSize,
            data: bundle,
          ),
        ),
      );
    } else if (bundle is DataItemResult) {
      task = task.copyWith(
        uploadItem: DataItemUploadItem(
          size: bundle.dataItemSize,
          data: bundle,
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
      debugPrint('Upload canceled while bundle was being created');
      throw Exception('Upload canceled');
    }

    final streamedUpload = _streamedUploadFactory.fromUploadType(task.type);

    final result =
        await streamedUpload.send(task.uploadItem!, wallet, (progress) {
      controller.updateProgress(
        task: task.copyWith(
          progress: progress,
        ),
      );
    });

    if (!result.success) {
      throw Exception('Failed to upload bundle');
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
  Future<void> uploadFolder({
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
        ),
      );
      controller.updateProgress(task: folderTask);
    } else {
      throw Exception('Unknown bundle type');
    }

    if (verifyCancel()) {
      print('Upload canceled after bundle creation and before upload');
      throw Exception('Upload canceled');
    }

    final streamedUpload =
        _streamedUploadFactory.fromUploadType(folderTask.type);

    final result =
        await streamedUpload.send(folderTask.uploadItem!, wallet, (progress) {
      folderTask = folderTask.copyWith(
        progress: progress,
      );
      controller.updateProgress(task: folderTask);
    });

    if (!result.success) {
      throw Exception('Failed to upload bundle');
    }

    controller.updateProgress(
      task: folderTask.copyWith(
        status: UploadStatus.complete,
      ),
    );
  }
}
