import 'dart:async';

import 'package:ardrive/utils/key_value_store.dart';
import 'package:ardrive_ui/ardrive_ui.dart';

/// The phone gallery's tile size, one of [galleryPhoneRowHeights], kept on
/// this device for every folder, as the phone photo apps keep theirs.
///
/// Read synchronously, so a gallery opens at its size rather than starting
/// at the default and jumping a frame later. [store] is set once at startup;
/// without it (tests, or before startup) the size is the default and is not
/// kept.
class GalleryPhoneTileSize {
  GalleryPhoneTileSize._();

  static KeyValueStore? store;

  static const key = 'gallery_phone_tile_size';

  /// The saved size, or the default when none, unknown or unreadable.
  static int read() {
    try {
      final stored = store?.getString(key);
      final value = stored is String ? int.tryParse(stored) : null;
      if (value == null ||
          value < 0 ||
          value >= galleryPhoneRowHeights.length) {
        return galleryPhoneDefaultSize;
      }
      return value;
    } catch (_) {
      return galleryPhoneDefaultSize;
    }
  }

  /// The default is forgotten rather than stored, as the view mode's is.
  static void write(int size) {
    final s = store;
    if (s == null) return;
    unawaited(() async {
      try {
        if (size == galleryPhoneDefaultSize) {
          await s.remove(key);
        } else {
          await s.putString(key, '$size');
        }
      } catch (_) {
        // The size still changes; it just is not remembered.
      }
    }());
  }
}
