import 'dart:async';

/// Token used to cancel sync operations in progress
class SyncCancellationToken {
  bool _isCancelled = false;
  final _cancelledController = StreamController<void>.broadcast();
  
  /// Whether the sync operation has been cancelled
  bool get isCancelled => _isCancelled;
  
  /// Stream that emits when cancellation is requested
  Stream<void> get onCancelled => _cancelledController.stream;
  
  /// Request cancellation of the sync operation
  void cancel() {
    if (!_isCancelled) {
      _isCancelled = true;
      _cancelledController.add(null);
    }
  }
  
  /// Check if cancelled and throw exception if so
  void checkCancellation() {
    if (_isCancelled) {
      throw SyncCancelledException();
    }
  }
  
  /// Clean up resources
  void dispose() {
    _cancelledController.close();
  }
}

/// Exception thrown when a sync operation is cancelled
class SyncCancelledException implements Exception {
  final String message;
  
  SyncCancelledException([this.message = 'Sync operation was cancelled']);
  
  @override
  String toString() => message;
}