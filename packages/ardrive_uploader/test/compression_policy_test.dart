import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:test/test.dart';

bool _ok(String name, {String type = 'text/plain', int length = 1000}) =>
    CompressionPolicy.isCompressible(
      fileName: name,
      contentType: type,
      length: length,
    );

/// The extensions @ar.io/deploy 2.1.2 never compresses, copied from its
/// `command-helpers` chunk, independently of the policy's own set.
const _deployDenylist = [
  '.7z', '.avif', '.br', '.bz2', '.gif', '.gz', '.heic', '.jpeg', '.jpg', //
  '.m4a', '.mp3', '.mp4', '.ogg', '.opus', '.png', '.rar', '.webm', '.webp',
  '.woff', '.woff2', '.xz', '.zip', '.zst',
];

void main() {
  group('CompressionPolicy.isCompressible', () {
    test('compresses the text and code a site is made of', () {
      for (final (name, type) in [
        ('index.html', 'text/html'),
        ('app.js', 'application/javascript'),
        ('app.mjs', 'text/javascript'),
        ('style.css', 'text/css'),
        ('data.json', 'application/json'),
        ('logo.svg', 'image/svg+xml'),
        ('main.wasm', 'application/wasm'),
        ('app.js.map', 'application/json'),
        ('README', 'application/octet-stream'),
        ('font.ttf', 'font/ttf'),
        ('feed.xml', 'application/xml'),
      ]) {
        expect(_ok(name, type: type), isTrue, reason: name);
      }
    });

    test('never compresses an extension @ar.io/deploy leaves alone', () {
      for (final ext in _deployDenylist) {
        expect(_ok('file$ext'), isFalse, reason: ext);
        expect(_ok('FILE${ext.toUpperCase()}'), isFalse, reason: 'upper $ext');
      }
    });

    test('never compresses what ArDrive adds: audio, video, pdf, images', () {
      for (final ext in [
        '.wav', '.flac', '.aac', '.mov', '.mkv', '.avi', '.m4v', '.3gp', //
        '.pdf', '.bmp', '.ico', '.tiff', '.tif', '.heif', '.jxl', '.apng',
        '.tgz', '.lz', '.lzma', '.jar', '.apk', '.dmg', '.iso', '.svgz',
      ]) {
        expect(_ok('file$ext'), isFalse, reason: ext);
      }
    });

    test('reads the content type too: whichever says no wins', () {
      expect(_ok('noext', type: 'video/mp4'), isFalse);
      expect(_ok('noext', type: 'audio/mpeg'), isFalse);
      expect(_ok('noext', type: 'image/png'), isFalse);
      expect(_ok('noext', type: 'image/jpeg'), isFalse);
      expect(_ok('noext', type: 'application/pdf'), isFalse);
      expect(_ok('noext', type: 'application/gzip'), isFalse);
      expect(_ok('noext', type: 'application/zip'), isFalse);
      expect(_ok('noext', type: 'IMAGE/PNG; charset=x'), isFalse);
      expect(
        _ok('manifest.json', type: 'application/x.arweave-manifest+json'),
        isFalse,
      );
    });

    test('SVG is compressed, PNG is not', () {
      expect(_ok('a.svg', type: 'image/svg+xml'), isTrue);
      expect(_ok('a.png', type: 'image/png'), isFalse);
    });

    test('a .gz is never compressed again, whatever it is called', () {
      expect(_ok('bundle.js.gz', type: 'application/gzip'), isFalse);
      expect(_ok('bundle.tar.gz'), isFalse);
      expect(_ok('.gz'), isFalse);
    });

    test('stops at 8 MiB and at nothing', () {
      const cap = 8 * 1024 * 1024;
      expect(CompressionPolicy.maxCompressibleBytes, cap);
      expect(_ok('a.js', length: cap), isTrue);
      expect(_ok('a.js', length: cap + 1), isFalse);
      expect(_ok('a.js', length: 0), isFalse);
    });
  });

  group('CompressionPolicy.gzipDeterministic', () {
    final text = Uint8List.fromList(
      utf8.encode('const a = "hello hello hello";\n' * 500),
    );

    test('gives a gzip that decodes to the original', () {
      final gz = CompressionPolicy.gzipDeterministic(text);
      expect(CompressionPolicy.looksGzipped(gz), isTrue);
      expect(GZipDecoder().decodeBytes(gz), text);
    });

    test('gives the same bytes at any time', () async {
      final first = CompressionPolicy.gzipDeterministic(text);
      // The header's modification time is the clock's, to the second.
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      final second = CompressionPolicy.gzipDeterministic(text);
      expect(second, first);
      expect(first.sublist(4, 8), [0, 0, 0, 0]);
      expect(first[9], 0xff);
    });
  });

  group('CompressionPolicy.compressIfSmaller', () {
    test('keeps the gzip when it is smaller', () {
      final text = Uint8List.fromList(utf8.encode('abc' * 1000));
      final gz = CompressionPolicy.compressIfSmaller(text);
      expect(gz, isNotNull);
      expect(gz!.length, lessThan(text.length));
    });

    test('keeps the file when the gzip is not smaller', () {
      // Random-looking bytes do not shrink; a few bytes cannot pay a header.
      final random = Random(42);
      final noise = Uint8List.fromList(
        List.generate(2048, (_) => random.nextInt(256)),
      );
      expect(CompressionPolicy.compressIfSmaller(noise), isNull);
      expect(
        CompressionPolicy.compressIfSmaller(Uint8List.fromList([1, 2, 3])),
        isNull,
      );
    });

    test('leaves bytes that are a gzip already', () {
      final once = CompressionPolicy.gzipDeterministic(
        Uint8List.fromList(utf8.encode('abc' * 1000)),
      );
      expect(CompressionPolicy.compressIfSmaller(once), isNull);
    });
  });
}
