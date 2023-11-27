import 'dart:async';

import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/data_bundler.dart';
import 'package:ardrive_uploader/src/utils/data_bundler_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/foundation.dart';

abstract class UploadStrategy {
  Future<void> uploadFile(
    FileUploadTask task,
    Wallet wallet,
    UploadController controller,
    bool Function() verifyCancel,
  );

  Future<void> uploadFolder({
    required FolderUploadTask task,
    required Wallet wallet,
    required UploadController controller,
    required bool Function() verifyCancel,
  });

  Future<void> upload({
    required UploadTask task,
    required Wallet wallet,
    required UploadController controller,
    required bool Function() verifyCancel,
  }) async {
    if (task is FileUploadTask) {
      return uploadFile(
        task,
        wallet,
        controller,
        verifyCancel,
      );
    } else if (task is FolderUploadTask) {
      return uploadFolder(
        task: task,
        wallet: wallet,
        controller: controller,
        verifyCancel: verifyCancel,
      );
    } else {
      throw Exception('Unknown upload task type');
    }
  }
}

class UploadFileUsingDataItemFiles extends UploadStrategy {
  final DataBundler _dataBundler;

  UploadFileUsingDataItemFiles({
    required DataBundler dataBundler,
  }) : _dataBundler = dataBundler;

  @override
  Future<void> uploadFile(FileUploadTask task, Wallet wallet,
      UploadController controller, bool Function() verifyCancel) async {
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

    /// sends the metadata item first
    final dataItemResults = await createDataItemResultFromDataItemFiles(
      dataItems,
      wallet,
    );

    final metadataItem = dataItemResults[0];

    final dataItem = dataItemResults[1];

    final metadataItemTask = task.copyWith(
      uploadItem: DataItemUploadItem(
        size: metadataItem.dataItemSize,
        data: metadataItem,
      ),
    );

    /// The upload can be canceled while the bundle is being created
    if (verifyCancel()) {
      debugPrint('Upload canceled while data item was being created');
      throw Exception('Upload canceled while metadata item was being created');
    }

    /// Note:
    /// We must use a different controller as we dont want to update the
    /// progress for sending the metadata. We only want to update the progress for
    /// sending the data item.
    ///
    /// It will ignore the updates for the upload of the metadata item.
    final metadataUploadController = UploadController(
      StreamController<UploadProgress>(),
      task.streamedUpload,
      _dataBundler,
    );

    final uploadResult = await metadataItemTask.streamedUpload.send(
      metadataItemTask,
      wallet,
      metadataUploadController,
    );

    if (!uploadResult.success) {
      throw Exception(
          'Failed to upload metadata item. DataItem won\'t be sent');
    }

    /// sends the data item
    final dataItemTask = task.copyWith(
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

    final result = await dataItemTask.streamedUpload.send(
      dataItemTask,
      wallet,
      controller,
    );

    if (!result.success) {
      throw Exception('Failed to upload data item');
    }

    controller.updateProgress(
      task: task.copyWith(
        status: UploadStatus.complete,
      ),
    );
  }

  @override
  Future<void> uploadFolder({
    required FolderUploadTask task,
    required Wallet wallet,
    required UploadController controller,
    required bool Function() verifyCancel,
  }) async {
    return _uploadFolder(
      task: task,
      wallet: wallet,
      controller: controller,
      verifyCancel: verifyCancel,
      dataBundler: _dataBundler,
    );
  }
}

class UploadFileUsingBundleStrategy extends UploadStrategy {
  final DataBundler _dataBundler;

  UploadFileUsingBundleStrategy({
    required DataBundler dataBundler,
  }) : _dataBundler = dataBundler;

  @override
  Future<void> uploadFile(
    FileUploadTask task,
    Wallet wallet,
    UploadController controller,
    bool Function() verifyCancel,
  ) async {
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

    final result = await task.streamedUpload.send(task, wallet, controller);

    if (!result.success) {
      throw Exception('Failed to upload bundle');
    }

    controller.updateProgress(
      task: task.copyWith(
        status: UploadStatus.complete,
      ),
    );
  }

  @override
  Future<void> uploadFolder({
    required FolderUploadTask task,
    required Wallet wallet,
    required UploadController controller,
    required bool Function() verifyCancel,
  }) {
    return _uploadFolder(
      task: task,
      wallet: wallet,
      controller: controller,
      verifyCancel: verifyCancel,
      dataBundler: _dataBundler,
    );
  }
}

Future<void> _uploadFolder({
  required FolderUploadTask task,
  required Wallet wallet,
  required UploadController controller,
  required bool Function() verifyCancel,
  required DataBundler dataBundler,
}) async {
  // creates the bundle for folders
  final bundle = await dataBundler.createDataBundleForEntities(
    entities: task.folders,
    wallet: wallet,
    driveKey: task.encryptionKey,
  );

  final folderBundle = (bundle).first.dataItemResult;

  if (folderBundle is TransactionResult) {
    controller.updateProgress(
      task: task.copyWith(
        uploadItem: TransactionUploadItem(
          size: folderBundle.dataSize,
          data: folderBundle,
        ),
      ),
    );
  } else if (bundle is DataItemResult) {
    controller.updateProgress(
      task: task.copyWith(
        uploadItem: DataItemUploadItem(
          size: folderBundle.dataItemSize,
          data: folderBundle,
        ),
      ),
    );
  } else {
    throw Exception('Unknown bundle type');
  }

  if (verifyCancel()) {
    print('Upload canceled after bundle creation and before upload');
    throw Exception('Upload canceled');
  }

  final result = await task.streamedUpload.send(task, wallet, controller);

  if (!result.success) {
    throw Exception('Failed to upload bundle');
  }

  controller.updateProgress(
    task: task.copyWith(
      status: UploadStatus.complete,
    ),
  );
}
