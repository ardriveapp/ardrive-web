import 'dart:typed_data';

import 'package:ardrive/utils/metadata_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stash/stash_api.dart';
import 'package:stash_memory/stash_memory.dart';

void main() {
  group('MetadataCache class', () {
    test('can be constructed out of a Cache', () async {
      final memoryCache = await newMockCache();

      expect(memoryCache, isInstanceOf<Cache<Uint8List>>());
      expect(MetadataCache(memoryCache), isInstanceOf<MetadataCache>());
    });

    test('will accept up to 10 entries', () async {
      final memoryCache = await newMockCache();
      final metadataCache = MetadataCache(memoryCache);

      final mockData = generateMockData(10);

      for (int i = 0; i < mockData.length; i++) {
        await metadataCache.put(i.toString(), mockData[i]);
        expect(await metadataCache.get(i.toString()), mockData[i]);
      }
    });

    test('eviction policy LFU', () async {
      final memoryCache = await newMockCache();
      final metadataCache = MetadataCache(memoryCache);

      final mockData = generateMockData(10);

      for (int i = 0; i < mockData.length; i++) {
        await metadataCache.put(i.toString(), mockData[i]);

        if (i != 0) {
          // These becomes the most frequently used items
          /// and zero becomes the least frequently used
          await metadataCache.get(i.toString());
          await metadataCache.get(i.toString());
          await metadataCache.get(i.toString());
        }
      }

      expect(await metadataCache.get('0'), isNotNull);

      await metadataCache.put('eleventh-item', Uint8List.fromList([1]));

      expect(
        await metadataCache.get('0'),
        null,
      );
    });
  });
}

List<Uint8List> generateMockData(int count) {
  final List<Uint8List> mockData = [];

  for (int i = 0; i < count; i++) {
    mockData.add(Uint8List.fromList([i]));
  }

  assert(mockData.length == count);

  return mockData;
}

Future<Cache<Uint8List>> newMockCache() async {
  final cacheStore = await newMemoryCacheStore();
  return MetadataCache.newCacheFromStore(cacheStore, maxEntries: 10);
}
