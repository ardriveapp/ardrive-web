import 'package:flutter/foundation.dart';

/// A view that opens photos straight to full screen (the gallery) asks
/// here before it selects the photo; the image preview that appears for it
/// goes to full screen at once. [onClosed] runs when that full screen closes.
class FullScreenPreviewRequest {
  FullScreenPreviewRequest._(this.onClosed, this._at);

  final VoidCallback? onClosed;
  final DateTime _at;

  /// A request not taken by then is dropped: the photo had no image preview
  /// (too large, say), and a later click in the list must not jump to full
  /// screen.
  static const lifetime = Duration(seconds: 10);

  static FullScreenPreviewRequest? _pending;

  static void request({VoidCallback? onClosed}) =>
      _pending = FullScreenPreviewRequest._(onClosed, DateTime.now());

  /// The pending request, once: whoever takes it honours it.
  static FullScreenPreviewRequest? take() {
    final pending = _pending;
    _pending = null;
    if (pending == null || DateTime.now().difference(pending._at) > lifetime) {
      return null;
    }
    return pending;
  }

  /// Drops a request nobody took, such as for a file that had no preview.
  static void cancel() => _pending = null;
}
