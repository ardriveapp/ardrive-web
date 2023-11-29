import 'dart:async';

import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/data_bundler.dart';
import 'package:ardrive_uploader/src/streamed_upload.dart';
import 'package:ardrive_uploader/src/utils/data_bundler_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/foundation.dart';

abstract class UploadStrategy {
  Future<void> uploadFile(
    List<DataItemFile> dataItems,
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
    required List<DataItemFile> dataItemFiles,
    required UploadTask task,
    required Wallet wallet,
    required UploadController controller,
    required bool Function() verifyCancel,
  }) async {
    if (task is FileUploadTask) {
      return uploadFile(dataItemFiles, task, wallet, controller, verifyCancel);
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
  final StreamedUploadFactory _streamedUploadFactory;

  UploadFileUsingDataItemFiles({
    required DataBundler dataBundler,
    required StreamedUploadFactory streamedUploadFactory,
  })  : _streamedUploadFactory = streamedUploadFactory,
        _dataBundler = dataBundler;

  @override
  Future<void> uploadFile(
    List<DataItemFile> dataItems,
    FileUploadTask task,
    Wallet wallet,
    UploadController controller,
    bool Function() verifyCancel,
  ) async {
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
        debugPrint('Progress: $progress');
        controller.updateProgress(
          task: dataItemTask.copyWith(
            progress: progress,
          ),
        );
      },
    );

    if (!result.success) {
      throw Exception('Failed to upload data item');
    }

    final updatedTask = controller.tasks[task.id]!;

    controller.updateProgress(
      task: updatedTask.copyWith(
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
  final StreamedUploadFactory _streamedUploadFactory;

  UploadFileUsingBundleStrategy({
    required DataBundler dataBundler,
    required StreamedUploadFactory streamedUploadFactory,
  })  : _dataBundler = dataBundler,
        _streamedUploadFactory = streamedUploadFactory;

  @override
  Future<void> uploadFile(
    List<DataItemFile> dataItems,
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
  // final bundle = await dataBundler.createDataBundleForEntities(
  //   entities: task.folders,
  //   wallet: wallet,
  //   driveKey: task.encryptionKey,
  // );

  // final folderBundle = (bundle).first.dataItemResult;

  // if (folderBundle is TransactionResult) {
  //   controller.updateProgress(
  //     task: task.copyWith(
  //       uploadItem: TransactionUploadItem(
  //         size: folderBundle.dataSize,
  //         data: folderBundle,
  //       ),
  //     ),
  //   );
  // } else if (bundle is DataItemResult) {
  //   controller.updateProgress(
  //     task: task.copyWith(
  //       uploadItem: DataItemUploadItem(
  //         size: folderBundle.dataItemSize,
  //         data: folderBundle,
  //       ),
  //     ),
  //   );
  // } else {
  //   throw Exception('Unknown bundle type');
  // }

  // if (verifyCancel()) {
  //   print('Upload canceled after bundle creation and before upload');
  //   throw Exception('Upload canceled');
  // }

  // final result = await task.streamedUpload.send(task, wallet, (progress) {
  //   controller.updateProgress(
  //     task: task.copyWith(
  //       progress: progress,
  //     ),
  //   );
  // });

  // if (!result.success) {
  //   throw Exception('Failed to upload bundle');
  // }

  // controller.updateProgress(
  //   task: task.copyWith(
  //     status: UploadStatus.complete,
  //   ),
  // );
}
