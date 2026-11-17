import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Which files of a deployment are uploaded gzipped, and how.
///
/// A deployment (a folder with a root `index.html`, uploaded to a public
/// drive) is served by gateways as a website. A gateway that finds
/// `Content-Encoding: gzip` on a data item sends it as it is, and the browser
/// decodes it, so text and code travel at about a third of their size. The
/// list of what is left alone is the one `@ar.io/deploy` 2.1.2 uses
/// (`--compress gzip`), plus the types ArDrive reads by byte range or that are
/// compressed already.
///
/// The tag is permanent once a data item is signed, so every rule here errs
/// towards leaving a file as it is.
class CompressionPolicy {
  const CompressionPolicy._();

  /// The largest file compressed. Compression holds the file and its gzip in
  /// memory, and the data item's size must be known before it is signed.
  static const int maxCompressibleBytes = 8 * 1024 * 1024;

  /// `Content-Encoding` value written on a compressed data item.
  static const String contentEncodingGzip = 'gzip';

  /// Extensions `@ar.io/deploy` 2.1.2 never compresses, verbatim.
  static const Set<String> arIoDeployDeniedExtensions = {
    '.7z',
    '.avif',
    '.br',
    '.bz2',
    '.gif',
    '.gz',
    '.heic',
    '.jpeg',
    '.jpg',
    '.m4a',
    '.mp3',
    '.mp4',
    '.ogg',
    '.opus',
    '.png',
    '.rar',
    '.webm',
    '.webp',
    '.woff',
    '.woff2',
    '.xz',
    '.zip',
    '.zst',
  };

  /// What ArDrive adds: audio and video (played by range requests), PDF,
  /// every image but SVG, and archives.
  static const Set<String> arDriveDeniedExtensions = {
    // audio and video
    '.aac', '.aif', '.aiff', '.flac', '.mid', '.midi', '.oga', '.wav', '.wma',
    '.weba', '.3gp', '.avi', '.flv', '.m4v', '.mkv', '.mov', '.mpeg', '.mpg',
    '.ogv', '.wmv',
    // documents served by range
    '.pdf',
    // images other than SVG
    '.apng', '.bmp', '.cur', '.heif', '.ico', '.jfif', '.jxl', '.psd', '.tif',
    '.tiff',
    // archives and packages
    '.apk', '.cab', '.dmg', '.iso', '.jar', '.lz', '.lz4', '.lzma', '.svgz',
    '.tbz2', '.tgz', '.txz',
  };

  static const Set<String> _deniedContentTypes = {
    'application/pdf',
    'application/gzip',
    'application/x-gzip',
    'application/zip',
    // A manifest is read by the gateway itself, never by a browser.
    'application/x.arweave-manifest+json',
  };

  /// Whether [fileName], of [contentType] and [length] bytes, may be
  /// compressed. Says nothing about whether it is worth it: see
  /// [compressIfSmaller].
  static bool isCompressible({
    required String fileName,
    required String contentType,
    required int length,
  }) {
    if (length <= 0 || length > maxCompressibleBytes) return false;

    final lowerName = fileName.toLowerCase();
    final extensionStart = lowerName.lastIndexOf('.');
    if (extensionStart >= 0) {
      final extension = lowerName.substring(extensionStart);
      if (arIoDeployDeniedExtensions.contains(extension) ||
          arDriveDeniedExtensions.contains(extension)) {
        return false;
      }
    }

    final type = contentType.split(';').first.trim().toLowerCase();
    if (type.startsWith('audio/') || type.startsWith('video/')) return false;
    if (type.startsWith('image/') && type != 'image/svg+xml') return false;
    if (_deniedContentTypes.contains(type)) return false;

    return true;
  }

  /// Whether [bytes] begin with the gzip magic number.
  static bool looksGzipped(List<int> bytes) =>
      bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;

  /// Gzips [raw] at level 9, the level `@ar.io/deploy` uses.
  ///
  /// The same bytes in give the same bytes out: `package:archive` stamps the
  /// header with the clock, so the modification time is set to 0 and the OS
  /// byte to a fixed value. A retried upload must sign the same data item.
  static Uint8List gzipDeterministic(List<int> raw) {
    final encoded = GZipEncoder().encode(raw, level: Deflate.BEST_COMPRESSION);
    final out = Uint8List.fromList(encoded!);
    // Header: magic(2) method(1) flags(1) mtime(4) xfl(1) os(1).
    out[4] = 0;
    out[5] = 0;
    out[6] = 0;
    out[7] = 0;
    out[8] = 0;
    out[9] = 0xff;
    return out;
  }

  /// The gzip of [raw], or null when it is not smaller or [raw] is a gzip
  /// already. A null means: upload the file untouched.
  static Uint8List? compressIfSmaller(Uint8List raw) {
    if (looksGzipped(raw)) return null;
    final gzipped = gzipDeterministic(raw);
    return gzipped.length < raw.length ? gzipped : null;
  }
}
