import 'package:arconnect/arconnect.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/streamed_upload.dart';
import 'package:ardrive_uploader/src/turbo_upload_service_base.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

class TurboStreamedUpload implements StreamedUpload<UploadTask, dynamic> {
  final TurboUploadService _turbo;
  final TabVisibilitySingleton _tabVisibility;

  TurboStreamedUpload(
    this._turbo, {
    TabVisibilitySingleton? tabVisibilitySingleton,
  }) : _tabVisibility = tabVisibilitySingleton ?? TabVisibilitySingleton();

  @override
  Future<dynamic> send(
    uploadTask,
    Wallet wallet,
    UploadController controller,
  ) async {
    final nonce = const Uuid().v4();

    final publicKey = await safeArConnectAction<String>(
      _tabVisibility,
      (_) async {
        return wallet.getOwner();
      },
    );

    final signature = await safeArConnectAction<String>(
      _tabVisibility,
      (_) async {
        return signNonceAndData(
          nonce: nonce,
          wallet: wallet,
        );
      },
    );

    uploadTask = uploadTask.copyWith(status: UploadStatus.inProgress);
    controller.updateProgress(task: uploadTask);

    /// If the file is larger than 500 MiB, we don't get progress updates.
    ///
    /// The TurboUploadServiceImpl for web uses fetch_client for the upload of files
    /// larger than 500 MiB. fetch_client does not support progress updates.
    if (kIsWeb && uploadTask.uploadItem!.size > MiB(500).size) {
      uploadTask.isProgressAvailable = false;
      controller.updateProgress(task: uploadTask);
    }

    // gets the streamed request
    final streamedRequest = _turbo
        .postStream(
            wallet: wallet,
            headers: {
              'x-nonce': nonce,
              'x-address': publicKey,
              'x-signature': signature,
            },
            dataItem: uploadTask.uploadItem!.data,
            size: uploadTask.uploadItem!.size,
            onSendProgress: (progress) {
              uploadTask.progress = progress;
              controller.updateProgress(task: uploadTask);
            })
        .then((value) async {
      if (!uploadTask.isProgressAvailable) {
        uploadTask.progress = 1;
      }

      uploadTask.status = UploadStatus.complete;

      controller.updateProgress(task: uploadTask);

      return value;
    }).onError((e, s) {
      uploadTask.status = UploadStatus.failed;
      controller.updateProgress(task: uploadTask);
    });

    return streamedRequest;
  }
}
