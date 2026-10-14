import 'dart:typed_data';

import 'package:ardrive/utils/preview_byte_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Uint8List bytes(int n) => Uint8List(n);

  test('hands back what it was given', () {
    final cache = PreviewByteCache(maxBytes: 100);

    cache.put('a', bytes(10));

    expect(cache.get('a')?.length, 10);
    expect(cache.get('missing'), isNull);
  });

  test('never holds more than its budget, dropping the oldest first', () {
    final cache = PreviewByteCache(maxBytes: 100);

    cache.put('a', bytes(40));
    cache.put('b', bytes(40));
    cache.put('c', bytes(40));

    expect(cache.totalBytes, lessThanOrEqualTo(100));
    expect(cache.get('a'), isNull);
    expect(cache.get('b'), isNotNull);
    expect(cache.get('c'), isNotNull);
  });

  test('a read counts as use, so what is looked at stays', () {
    final cache = PreviewByteCache(maxBytes: 100);

    cache.put('a', bytes(40));
    cache.put('b', bytes(40));
    cache.get('a');
    cache.put('c', bytes(40));

    expect(cache.get('a'), isNotNull);
    expect(cache.get('b'), isNull);
  });

  test('a file bigger than the whole budget is not kept at all', () {
    final cache = PreviewByteCache(maxBytes: 100);

    cache.put('small', bytes(30));
    cache.put('huge', bytes(101));

    expect(cache.get('huge'), isNull);
    expect(cache.get('small'), isNotNull,
        reason: 'one oversized file must not throw everything else out');
  });

  test('putting the same key again replaces it, and counts it once', () {
    final cache = PreviewByteCache(maxBytes: 100);

    cache.put('a', bytes(60));
    cache.put('a', bytes(30));

    expect(cache.length, 1);
    expect(cache.totalBytes, 30);
  });

  test('clear forgets everything', () {
    final cache = PreviewByteCache(maxBytes: 100);

    cache.put('a', bytes(10));
    cache.put('b', bytes(10));
    cache.clear();

    expect(cache.length, 0);
    expect(cache.totalBytes, 0);
    expect(cache.get('a'), isNull);
  });
}
