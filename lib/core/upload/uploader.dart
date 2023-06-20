import 'package:ardrive/blocs/upload/upload_handles/handles.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/services/turbo/upload_service.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:async/async.dart';
import 'package:tuple/tuple.dart';

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
    final StreamGroup<Tuple2<int, double>> uploadProgressGroup =
        StreamGroup<Tuple2<int, double>>();

    final List<double> progresses = List.filled(
      bundleHandles.length + fileV2Handles.length,
      0.0,
    );

    int index = 0;

    for (final bundleHandle in bundleHandles) {
      await uploadProgressGroup.add(
        _uploadItem(
          index: index++,
          itemHandle: bundleHandle,
          prepare: _prepareBundle,
          upload: _bundleUploader.upload,
          onFinishUpload: _onFinishBundleUpload,
          onUploadError: _onUploadBundleError,
          dispose: (handle) =>
              handle.dispose(useTurbo: _bundleUploader._useTurbo),
        ),
      );
    }

    for (final fileV2Handle in fileV2Handles) {
      await uploadProgressGroup.add(
        _uploadItem(
          index: index++,
          itemHandle: fileV2Handle,
          prepare: _prepareFile,
          upload: _fileV2Uploader.upload,
          onFinishUpload: _onFinishFileUpload,
          onUploadError: _onUploadFileError,
          dispose: (handle) => handle.dispose(),
        ),
      );
    }

    await for (final progress in uploadProgressGroup.stream) {
      progresses[progress.item1] = progress.item2;
      final totalProgress =
          progresses.reduce((a, b) => a + b) / progresses.length;

      yield progresses.reduce((a, b) => a + b) / progresses.length;

      if (totalProgress == 1.0) {
        break;
      }
    }
  }

  Stream<Tuple2<int, double>> _uploadItem<T>({
    required T itemHandle,
    required int index,
    required Future<void> Function(T handle) prepare,
    required Stream<double> Function(T handle) upload,
    required Future<void> Function(T handle) onFinishUpload,
    required Future<void> Function(T handle, Object error) onUploadError,
    required void Function(T handle) dispose,
  }) async* {
    try {
      final itemString = itemHandle.toString();

      logger.i('Preparing $itemString');

      await prepare(itemHandle);

      bool hasError = false;

      await for (var progress in upload(itemHandle).handleError((e, s) {
        logger.e('Handling error on ArDriveUploader with $itemString', e, s);
        hasError = true;
      })) {
        yield Tuple2(index, progress);
      }

      if (hasError) {
        logger.d(
            'Error in ${itemString.toString()} upload, breaking upload for $itemString');
        logger.i('Disposing ${itemString.toString()}');

        dispose(itemHandle);

        throw Exception();
      }

      logger.i('Finished uploading $itemString');
      logger.i('Disposing $itemString');
      dispose(itemHandle);

      await onFinishUpload(itemHandle);
    } catch (e, stacktrace) {
      logger.e('Error in ${itemHandle.toString()} upload', e, stacktrace);
      await onUploadError(itemHandle, e);
    }
  }
}

class BundleUploader extends Uploader<BundleUploadHandle> {
  final TurboUploader _turbo;
  final ArweaveBundleUploader _arweave;
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
    await _turbo
        .postDataItem(dataItem: handle.bundleDataItem, wallet: _wallet)
        .onError((error, stackTrace) {
      logger.e(error);
      throw Exception();
    });
    handle.setUploadProgress(1);
    yield 1;
  }
}

class ArweaveBundleUploader implements Uploader<BundleUploadHandle> {
  final Arweave _arweave;

  ArweaveBundleUploader(this._arweave);

  @override
  Stream<double> upload(handle) async* {
    yield* _arweave.transactions
        .upload(handle.bundleTx,
            maxConcurrentUploadCount: maxConcurrentUploadCount)
        .map((upload) {
      handle.setUploadProgress(upload.progress);
      return upload.progress;
    });
  }
}

class FileV2Uploader implements Uploader<FileV2UploadHandle> {
  final Arweave _arweave;

  FileV2Uploader(this._arweave);

  @override
  Stream<double> upload(handle) async* {
    yield* _arweave.transactions
        .upload(handle.entityTx, maxConcurrentUploadCount: 1)
        .map((upload) {
      return upload.progress;
    });
  }
}
