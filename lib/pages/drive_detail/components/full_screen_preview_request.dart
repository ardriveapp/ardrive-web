import 'package:flutter/foundation.dart';

/// A view that opens photos straight to full screen (the gallery) asks
/// here before it selects the photo; that photo's image preview goes to full
/// screen at once. [onClosed] runs when that full screen closes.
class FullScreenPreviewRequest {
  FullScreenPreviewRequest._(this.fileId, this.onClosed, this._at);

  /// The photo it is for: only that photo's preview takes it.
  final String fileId;
  final VoidCallback? onClosed;
  final DateTime _at;

  /// A request not taken by then is dropped: the photo had no image preview
  /// (too large, say), and a later click must not jump to full screen.
  static const lifetime = Duration(seconds: 10);

  static FullScreenPreviewRequest? _pending;

  static void request({required String fileId, VoidCallback? onClosed}) =>
      _pending = FullScreenPreviewRequest._(fileId, onClosed, DateTime.now());

  /// The pending request for [fileId], once: whoever takes it honours it.
  /// One for another photo is left; one too old is dropped.
  static FullScreenPreviewRequest? take(String? fileId) {
    final pending = _pending;
    if (pending == null) return null;
    if (DateTime.now().difference(pending._at) > lifetime) {
      _pending = null;
      return null;
    }
    if (pending.fileId != fileId) return null;
    _pending = null;
    return pending;
  }

  /// Drops a request nobody took.
  static void cancel() => _pending = null;

  /// Drops the request for [fileId], whose preview turned out not to be an
  /// image the full screen can show (too large, unavailable, failed).
  static void cancelFor(String? fileId) {
    if (_pending?.fileId == fileId) _pending = null;
  }
}
