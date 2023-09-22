import 'dart:async';

import 'package:ardrive_uploader/src/arfs_upload_metadata.dart';

// TODO: Review this file
abstract class UploadController {
  abstract final ARFSUploadMetadata metadata;

  void close();
  void cancel();
  void onCancel();
  void onDone(Function(ARFSUploadMetadata metadata) callback);
  void onError(Function() callback);
  void updateProgress(double progress);
  void onProgressChange(Function(double progress) callback);

  factory UploadController(
    ARFSUploadMetadata metadata,
    StreamController<double> progressStream,
  ) {
    return _UploadController(
      metadata: metadata,
      progressStream: progressStream,
    );
  }
}

class _UploadController implements UploadController {
  final StreamController<double> _progressStream;

  _UploadController({
    required this.metadata,
    required StreamController<double> progressStream,
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
        print('Progress on subscriptiobn: $event');
        _onProgressChange!(event);
      },
      onDone: () {
        print('Done');
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
  void updateProgress(double progress) {
    print('updating Progress: $progress');
    _progressStream.add(progress);
  }

  @override
  void onError(Function() callback) {
    // TODO: implement onError
  }

  @override
  void onProgressChange(Function(double progress) callback) {
    _onProgressChange = callback;
  }

  void Function(double progress)? _onProgressChange = (progress) {
    print('Progress: $progress');
  };

  void Function(ARFSUploadMetadata metadata) _onDone =
      (ARFSUploadMetadata metadata) {
    print('Upload Finished');
  };

  @override
  final ARFSUploadMetadata metadata;
}
