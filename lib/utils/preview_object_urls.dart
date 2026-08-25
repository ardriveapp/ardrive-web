import 'dart:typed_data';

import 'package:ardrive/utils/logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;

/// Turns bytes that are already in memory into a URL a media element can play.
///
/// A private file has no URL a player can fetch: every gateway holds only
/// ciphertext, so the bytes have to be decrypted here and handed to the player
/// from memory. On the web that is what a blob URL is for.
///
/// The invariant of `docs/FILE_SHARING_REDESIGN_PLAN.md` §4.3 bounds what these
/// URLs may be used for. A blob URL inherits *this* origin, so a URL from here
/// may only ever reach an `<audio>` or `<video>` element - which cannot execute
/// script, and which §4.3 names as the acceptable case - and must never reach
/// an `<iframe>`, `<embed>`, `<object>`, or anything else that would let bytes
/// from an untrusted transaction run as script on `app.ardrive.io`.
///
/// Injected into `FsEntryPreviewCubit` rather than called as a top-level
/// function so a test can exercise the private-media path without a browser.
class PreviewObjectUrls {
  /// A URL for [bytes], or `null` when this platform cannot make one.
  ///
  /// Off the web there is neither a blob URL nor a media element to give one
  /// to: `universal_html` would hand back a string from its simulated DOM that
  /// no native player can open, so nothing is created and the caller falls back
  /// to "preview unavailable" instead of a player that fails to load.
  String? create(Uint8List bytes, String contentType) {
    if (!kIsWeb) {
      return null;
    }

    try {
      return html.Url.createObjectUrlFromBlob(
        html.Blob(<dynamic>[bytes], contentType),
      );
    } catch (e) {
      logger.w('Could not create an in-memory preview URL: $e');

      return null;
    }
  }

  /// Releases [url] and the bytes the browser is holding behind it.
  void revoke(String url) {
    if (!kIsWeb) {
      return;
    }

    try {
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      logger.w('Could not revoke an in-memory preview URL: $e');
    }
  }
}
