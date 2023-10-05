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
    handle,
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

    handle = handle.copyWith(status: UploadStatus.inProgress);
    controller.updateProgress(task: handle);

    if (kIsWeb && handle.uploadItem!.size > 1024 * 1024 * 500) {
      handle.isProgressAvailable = false;
      controller.updateProgress(task: handle);
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
            dataItem: handle.uploadItem!.data,
            size: handle.uploadItem!.size,
            onSendProgress: (progress) {
              handle.progress = progress;
              controller.updateProgress(task: handle);

              if (progress == 1) {
                handle.status = UploadStatus.complete;
                controller.updateProgress(task: handle);
              }
            })
        .then((value) async {
      if (!handle.isProgressAvailable) {
        print('Progress is not available, setting to 1');
        handle.progress = 1;
      }

      controller.updateProgress(
        task: handle,
      );

      return value;
    }).onError((e, s) {
      print(e.toString());
      handle.status = UploadStatus.failed;
      controller.updateProgress(task: handle);
    });

    return streamedRequest;
  }
}
