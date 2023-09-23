import 'package:arconnect/arconnect.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/turbo_upload_service_base.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:uuid/uuid.dart';

abstract class StreamedUpload<T, R> {
  Future<R> send(
    T handle,
    Wallet wallet,
    UploadController controller,
  );
}

class TurboStreamedUpload implements StreamedUpload<DataItemResult, dynamic> {
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

    print(
        'Sending request to turbo. Is possible get progress: ${controller.isPossibleGetProgress}');

    // gets the streamed request
    final streamedRequest = _turbo
        .postStream(
            controller: controller,
            wallet: wallet,
            headers: {
              'x-nonce': nonce,
              'x-address': publicKey,
              'x-signature': signature,
            },
            dataItem: handle,
            size: handle.dataItemSize,
            onSendProgress: (progress) {
              controller.updateProgress(
                ArDriveUploadProgress(
                  progress,
                  UploadStatus.inProgress,
                  handle.dataItemSize,
                  controller.isPossibleGetProgress,
                ),
              );
            })
        .then((value) {
      print('Turbo response: ${value.statusCode}');
      controller.updateProgress(ArDriveUploadProgress(1, UploadStatus.complete,
          handle.dataItemSize, controller.isPossibleGetProgress));
      controller.close();

      return value;
    });

    return streamedRequest;
  }
}
