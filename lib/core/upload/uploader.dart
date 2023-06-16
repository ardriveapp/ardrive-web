import 'package:ardrive/blocs/upload/upload_handles/handles.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/turbo/upload_service.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:rxdart/rxdart.dart';

class ArDriveUploader {
  final BundleUploader _bundleUploader;
  final FileV2Uploader _fileV2Uploader;
  final Future<void> Function(BundleUploadHandle handle) _prepareBundle;
  final Future<void> Function(FileV2UploadHandle handle) _prepareFile;
  final Future<void> Function(BundleUploadHandle handle) _onFinishBundleUpload;
  final Future<void> Function(FileV2UploadHandle handle) _onFinishFileUpload;
  final Future<void> Function(BundleUploadHandle handle, Object error)
      _onUploadBundleError;
  final Future<void> Function(FileV2UploadHandle handle, Object error)
      _onUploadFileError;

  ArDriveUploader({
    required BundleUploader bundleUploader,
    required FileV2Uploader fileV2Uploader,
    required Future<void> Function(BundleUploadHandle handle) prepareBundle,
    required Future<void> Function(FileV2UploadHandle handle) prepareFile,
    required Future<void> Function(BundleUploadHandle handle)
        onFinishBundleUpload,
    required Future<void> Function(FileV2UploadHandle handle)
        onFinishFileUpload,
    required Future<void> Function(BundleUploadHandle handle, Object error)
        onUploadBundleError,
    required Future<void> Function(FileV2UploadHandle handle, Object error)
        onUploadFileError,
  })  : _bundleUploader = bundleUploader,
        _fileV2Uploader = fileV2Uploader,
        _prepareBundle = prepareBundle,
        _prepareFile = prepareFile,
        _onFinishBundleUpload = onFinishBundleUpload,
        _onFinishFileUpload = onFinishFileUpload,
        _onUploadBundleError = onUploadBundleError,
        _onUploadFileError = onUploadFileError;

  Stream<double> uploadFromHandles({
    List<BundleUploadHandle> bundleHandles = const [],
    List<FileV2UploadHandle> fileV2Handles = const [],
  }) async* {
    for (final bundleHandle in bundleHandles) {
      yield* _uploadItem(
        itemHandle: bundleHandle,
        prepare: _prepareBundle,
        upload: _bundleUploader.upload,
        onFinishUpload: _onFinishBundleUpload,
        onUploadError: _onUploadBundleError,
        dispose: (handle) =>
            handle.dispose(useTurbo: _bundleUploader._useTurbo),
        itemName: 'bundle',
      );
    }

    for (final fileV2Handle in fileV2Handles) {
      yield* _uploadItem(
        itemHandle: fileV2Handle,
        prepare: _prepareFile,
        upload: _fileV2Uploader.upload,
        onFinishUpload: _onFinishFileUpload,
        onUploadError: _onUploadFileError,
        dispose: (handle) => handle.dispose(),
        itemName: 'file',
      );
    }
  }

  Stream<double> _uploadItem<T>({
    required T itemHandle,
    required Future<void> Function(T handle) prepare,
    required Stream<double> Function(T handle) upload,
    required Future<void> Function(T handle) onFinishUpload,
    required Future<void> Function(T handle, Object error) onUploadError,
    required void Function(T handle) dispose,
    required String itemName,
  }) async* {
    try {
      await prepare(itemHandle);
      bool hasError = false;

      await for (var progress in upload(itemHandle).handleError((e, s) {
        logger.e('Handling error on ArDriveUploader with $itemName', e, s);
        hasError = true;
      }).debounceTime(const Duration(milliseconds: 500))) {
        yield progress;
      }

      if (hasError) {
        logger.d('Error in $itemName upload, breaking upload for $itemHandle');

        logger.i('Disposing $itemName');
        dispose(itemHandle);

        throw Exception();
      }

      logger.i('Finished uploading $itemName');

      logger.i('Disposing $itemName');
      dispose(itemHandle);

      await onFinishUpload(itemHandle);
    } catch (e, stacktrace) {
      logger.e('Error in $itemName upload', e, stacktrace);
      await onUploadError(itemHandle, e);
    }
  }
}

class BundleUploader extends Uploader<BundleUploadHandle> {
  final TurboUploader _turbo;
  final ArweaveBunldeUploader _arweave;
  final bool _useTurbo;

  late Uploader _uploader;

  BundleUploader(
    this._turbo,
    this._arweave, {
    bool useTurbo = false,
  }) : _useTurbo = useTurbo {
    logger.i('Creating BundleUploader');

    if (_useTurbo) {
      logger.i('Using TurboUploader');

      _uploader = _turbo;
    } else {
      logger.i('Using ArweaveBunldeUploader');

      _uploader = _arweave;
    }
  }

  @override
  Stream<double> upload(BundleUploadHandle handle) async* {
    yield* _uploader.upload(handle);
  }

  @override
  String toString() {
    return 'BundleUploader{_turbo: $_turbo, _arweave: $_arweave, _useTurbo: $_useTurbo}';
  }
}

abstract class Uploader<T extends UploadHandle> {
  Stream<double> upload(
    T handle,
  );
}

class TurboUploader implements Uploader<BundleUploadHandle> {
  final TurboUploadService _turbo;
  final Wallet _wallet;

  TurboUploader(this._turbo, this._wallet);

  @override
  Stream<double> upload(handle) async* {
    try {
      await _turbo
          .postDataItem(dataItem: handle.bundleDataItem, wallet: _wallet)
          .onError((error, stackTrace) {
        logger.e(error);
        logger.d('Throwing exception');
        throw Exception();
      });
      yield 1;
    } catch (e, stacktrace) {
      logger.e('Error in turbo upload', e, stacktrace);
      throw Exception();
    }
  }
}

class ArweaveBunldeUploader implements Uploader<BundleUploadHandle> {
  final ArweaveService _arweave;

  ArweaveBunldeUploader(this._arweave);

  @override
  Stream<double> upload(handle) async* {
    yield* _arweave.client.transactions
        .upload(handle.bundleTx,
            maxConcurrentUploadCount: maxConcurrentUploadCount)
        .map((upload) {
      return upload.progress;
    });
  }
}

class FileV2Uploader implements Uploader<FileV2UploadHandle> {
  final ArweaveService _arweave;

  FileV2Uploader(this._arweave);

  @override
  Stream<double> upload(handle) async* {
    yield* _arweave.client.transactions
        .upload(handle.entityTx, maxConcurrentUploadCount: 1)
        .map((upload) {
      return upload.progress;
    });
  }
}
