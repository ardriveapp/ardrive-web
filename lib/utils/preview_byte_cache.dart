import 'dart:collection';
import 'dart:typed_data';

/// The bytes of recently previewed files, held to a total size.
///
/// What this replaced was a memory vault with no bound at all: every image,
/// document and email previewed in a session stayed in the tab until it closed,
/// and survived logout. Most of that is never looked at twice.
///
/// Least recently used goes first. A file bigger than the whole budget is not
/// held at all - keeping it would mean throwing out everything else for one
/// file that is unlikely to be asked for again.
///
/// What goes in is what came off the gateway: ciphertext for a private file,
/// which is decrypted after it is read from here. Nothing decrypted is kept.
class PreviewByteCache {
  PreviewByteCache({this.maxBytes = defaultMaxBytes});

  /// Room for a handful of documents and photos. A preview over the 25 MiB
  /// on-request threshold is something the reader asked for on purpose, and is
  /// cheap to ask for again from the browser's own HTTP cache.
  static const int defaultMaxBytes = 50 * 1024 * 1024;

  final int maxBytes;

  // Insertion order is recency order: a read moves an entry to the end.
  final LinkedHashMap<String, Uint8List> _entries = LinkedHashMap();
  int _totalBytes = 0;

  int get totalBytes => _totalBytes;

  int get length => _entries.length;

  Uint8List? get(String key) {
    final bytes = _entries.remove(key);

    if (bytes != null) {
      _entries[key] = bytes;
    }

    return bytes;
  }

  void put(String key, Uint8List bytes) {
    final previous = _entries.remove(key);

    if (previous != null) {
      _totalBytes -= previous.lengthInBytes;
    }

    if (bytes.lengthInBytes > maxBytes) {
      return;
    }

    while (
        _totalBytes + bytes.lengthInBytes > maxBytes && _entries.isNotEmpty) {
      final oldest = _entries.keys.first;
      _totalBytes -= _entries.remove(oldest)!.lengthInBytes;
    }

    _entries[key] = bytes;
    _totalBytes += bytes.lengthInBytes;
  }

  void clear() {
    _entries.clear();
    _totalBytes = 0;
  }
}
