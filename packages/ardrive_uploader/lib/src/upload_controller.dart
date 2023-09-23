import 'dart:async';

import '../ardrive_uploader.dart';

// TODO: Review this file
abstract class UploadController {
  abstract final ARFSUploadMetadata metadata;

  void close();
  void cancel();
  void onCancel();
  void onDone(Function(ARFSUploadMetadata metadata) callback);
  void onError(Function() callback);
  void updateProgress(ArDriveUploadProgress progress);
  void onProgressChange(Function(ArDriveUploadProgress progress) callback);

  bool get isPossibleGetProgress;
  set isPossibleGetProgress(bool value);

  factory UploadController(
    ARFSUploadMetadata metadata,
    StreamController<ArDriveUploadProgress> progressStream,
  ) {
    return _UploadController(
      metadata: metadata,
      progressStream: progressStream,
    );
  }
}

class _UploadController implements UploadController {
  final StreamController<ArDriveUploadProgress> _progressStream;

  _UploadController({
    required this.metadata,
    required StreamController<ArDriveUploadProgress> progressStream,
  }) : _progressStream = progressStream {
    init();
  }

  bool _isCanceled = false;

  bool get isCanceled => _isCanceled;

  void init() {
    _isCanceled = false;
    late StreamSubscription subscription;

    subscription = _progressStream.stream.listen(
      (event) {
        _onProgressChange!(event);
        print('Progress: ${event.progress}');
      },
      onDone: () {
        print('Done upload');
        _onDone(metadata);
        subscription.cancel();
      },
      onError: (err) {
        print('Error: $err');
        subscription.cancel();
      },
    );
  }

  @override
  void close() {
    _progressStream.close();
  }

  @override
  void cancel() {
    _isCanceled = true;
    _progressStream.close();
  }

  @override
  void onCancel() {
    // _onCancel();
  }

  @override
  void onDone(Function(ARFSUploadMetadata metadata) callback) {
    _onDone = callback;
  }

  @override
  void updateProgress(ArDriveUploadProgress progress) {
    print('Update progress: ${progress.status}');
    if (_isPossibleGetProgress) {
      _progressStream.add(progress);
    } else {
      _progressStream.add(
          ArDriveUploadProgress(0, progress.status, progress.totalSize, false));
    }
  }

  @override
  void onError(Function() callback) {
    // TODO: implement onError
  }

  @override
  void onProgressChange(Function(ArDriveUploadProgress progress) callback) {
    _onProgressChange = callback;
  }

  void Function(ArDriveUploadProgress progress)? _onProgressChange =
      (progress) {};

  void Function(ARFSUploadMetadata metadata) _onDone =
      (ARFSUploadMetadata metadata) {
    print('Upload Finished');
  };

  @override
  final ARFSUploadMetadata metadata;

  @override
  bool get isPossibleGetProgress => _isPossibleGetProgress;

  @override
  set isPossibleGetProgress(bool value) => _isPossibleGetProgress = value;

  bool _isPossibleGetProgress = true;
}
