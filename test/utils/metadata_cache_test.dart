import 'dart:typed_data';

import 'package:ardrive/utils/metadata_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stash/stash_api.dart';
import 'package:stash_memory/stash_memory.dart';
import 'package:stash_shared_preferences/stash_shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MetadataCache class', () {
    test('can be constructed out of a Cache Store', () async {
      final CacheStore cacheStore = await newMemoryCacheStore();

      expect(
        await MetadataCache.fromCacheStore(cacheStore),
        isInstanceOf<MetadataCache>(),
      );
    });

    test('can take as many entries as the maxEntries limit', () async {
      final metadataCache = await MetadataCache.fromCacheStore(
        await newMemoryCacheStore(),
        maxEntries: 10,
      );

      final mockData = generateMockData(10);

      for (int i = 0; i < mockData.length; i++) {
        await metadataCache.put(i.toString(), mockData[i]);
        expect(await metadataCache.get(i.toString()), mockData[i]);
      }

      final keys = await metadataCache.keys;
      expect(keys, ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']);
    });

    test('follows the eviction policy: Least Frequently Used (LFU)', () async {
      // Refer to https://pub.dev/packages/stash#eviction-policies for more info
      /// LfuEvictionPolicy	LFU (least-frequently used) policy counts how often
      /// an entry is used. Those that are least often used are discarded first.
      /// In that sense it works very similarly to LRU except that instead of
      /// storing the value of how recently a block was accessed, it stores the
      /// value of how many times it was accessed

      final metadataCache = await MetadataCache.fromCacheStore(
        await newMemoryCacheStore(),
        maxEntries: 10,
      );

      final mockData = generateMockData(10);

      for (int i = 0; i < mockData.length; i++) {
        await metadataCache.put(i.toString(), mockData[i]);

        if (i != 0) {
          // These becomes the most frequently used items
          /// and zero becomes the least frequently used
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

      final keys = await metadataCache.keys;
      expect(
        keys,
        ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'eleventh-item'],
      );
    });

    test('can remove added items', () async {
      final metadataCache = await MetadataCache.fromCacheStore(
        await newMemoryCacheStore(),
        maxEntries: 10,
      );

      final mockData = generateMockData(10);

      for (int i = 0; i < mockData.length; i++) {
        await metadataCache.put(i.toString(), mockData[i]);
        expect(await metadataCache.get(i.toString()), mockData[i]);
        await metadataCache.remove(i.toString());
        expect(await metadataCache.get(i.toString()), null);
      }
    });

    test('can be cleared', () async {
      final metadataCache = await MetadataCache.fromCacheStore(
        await newMemoryCacheStore(),
        maxEntries: 10,
      );

      final mockData = generateMockData(10);

      for (int i = 0; i < mockData.length; i++) {
        await metadataCache.put(i.toString(), mockData[i]);
      }

      final keys = await metadataCache.keys;
      expect(keys, ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']);

      await metadataCache.clear();

      final keysAfterClear = await metadataCache.keys;
      expect(keysAfterClear, []);
    });

    group('with a stash_shared_preferences cache', () {
      late MetadataCache metadataCache;

      setUpAll(() {
        SharedPreferences.setMockInitialValues({});
      });

      test('can be constructed', () async {
        final store = await newSharedPreferencesCacheStore();
        metadataCache = await MetadataCache.fromCacheStore(
          store,
          maxEntries: 1,
        );

        expect(metadataCache, isInstanceOf<MetadataCache>());
      });

      test('can write and read data', () async {
        final fibonacciSequence = [0, 1, 1, 2, 3, 5, 8, 13, 21];

        await metadataCache.put(
          'fibonacci',
          Uint8List.fromList(fibonacciSequence),
        );

        final storedData = await metadataCache.get('fibonacci');
        expect(storedData, Uint8List.fromList(fibonacciSequence));

        final keys = await metadataCache.keys;
        expect(keys, ['fibonacci']);
      });
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
