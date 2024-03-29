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

    test('size indicates the number of entries in the cache', () async {
      final metadataCache = await MetadataCache.fromCacheStore(
        await newMemoryCacheStore(),
        maxEntries: 10,
      );

      final mockData = generateMockData(1)[0];

      await metadataCache.put('0', mockData);

      expect(await metadataCache.size, 1);
    });

    test('isFull indicates whether the cache is at max capacity', () async {
      final metadataCache = await MetadataCache.fromCacheStore(
        await newMemoryCacheStore(),
        maxEntries: 10,
      );

      final mockData = generateMockData(10);

      for (int i = 0; i < mockData.length; i++) {
        final wasPut = await metadataCache.put(i.toString(), mockData[i]);
        expect(wasPut, true);
      }

      expect(await metadataCache.isFull, true);
    });

    test('follows the eviction policy: no eviction', () async {
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
        final wasPut = await metadataCache.put(i.toString(), mockData[i]);
        expect(wasPut, true);
      }

      expect(
        await metadataCache.keys,
        ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'],
      );

      final wasEleventhItemPut = await metadataCache.put(
        'eleventh-item',
        Uint8List.fromList([1]),
      );
      expect(wasEleventhItemPut, false);

      expect(
        await metadataCache.get('eleventh-item'),
        null,
      );

      expect(
        await metadataCache.keys,
        ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'],
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

  return mockData;
}
