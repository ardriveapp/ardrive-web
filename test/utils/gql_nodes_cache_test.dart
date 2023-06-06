import 'dart:typed_data';

import 'package:ardrive/utils/gql_nodes_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stash/stash_api.dart';
import 'package:stash_memory/stash_memory.dart';
import 'package:stash_shared_preferences/stash_shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MetadataCache class', () {
    const mockDriveId = 'mockDriveId';
    const mockDriveId2 = 'mockDriveId2';

    test('can be constructed out of a Cache Store', () async {
      final CacheStore cacheStore = await newMemoryCacheStore();

      expect(
        await GQLNodesCache.fromCacheStore(cacheStore),
        isInstanceOf<GQLNodesCache>(),
      );
    });

    test('can take as many entries as the maxEntries limit', () async {
      final metadataCache = await GQLNodesCache.fromCacheStore(
        await newMemoryCacheStore(),
        maxEntries: 10,
      );

      final mockData = generateMockData(10);

      for (int i = 0; i < mockData.length; i++) {
        await metadataCache.put(mockDriveId, mockData[i]);
        expect(await metadataCache.get(mockDriveId, i), mockData[i]);
      }

      final keys = await metadataCache.keys;
      expect(keys, [
        'mockDriveId_0',
        'mockDriveId_1',
        'mockDriveId_2',
        'mockDriveId_3',
        'mockDriveId_4',
        'mockDriveId_5',
        'mockDriveId_6',
        'mockDriveId_7',
        'mockDriveId_8',
        'mockDriveId_9',
      ]);
    });

    test('size indicates the number of entries in the cache', () async {
      final metadataCache = await GQLNodesCache.fromCacheStore(
        await newMemoryCacheStore(),
        maxEntries: 10,
      );

      final mockData = generateMockData(1)[0];

      await metadataCache.put(mockDriveId, mockData);

      expect(await metadataCache.size, 1);
    });

    test('isFull indicates whether the cache is at max capacity', () async {
      final metadataCache = await GQLNodesCache.fromCacheStore(
        await newMemoryCacheStore(),
        maxEntries: 10,
      );

      expect(await metadataCache.isFull, false);

      final mockData = generateMockData(10);

      for (int i = 0; i < mockData.length; i++) {
        final wasPut = await metadataCache.put(mockDriveId, mockData[i]);
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

      final metadataCache = await GQLNodesCache.fromCacheStore(
        await newMemoryCacheStore(),
        maxEntries: 10,
      );

      final mockData = generateMockData(10);

      for (int i = 0; i < mockData.length; i++) {
        final wasPut = await metadataCache.put(mockDriveId, mockData[i]);
        expect(wasPut, true);
      }

      expect(
        await metadataCache.keys,
        [
          'mockDriveId_0',
          'mockDriveId_1',
          'mockDriveId_2',
          'mockDriveId_3',
          'mockDriveId_4',
          'mockDriveId_5',
          'mockDriveId_6',
          'mockDriveId_7',
          'mockDriveId_8',
          'mockDriveId_9',
        ],
      );

      final wasEleventhItemPut = await metadataCache.put(
        mockDriveId,
        newMockItem(0),
      );
      expect(wasEleventhItemPut, false);

      expect(
        await metadataCache.get(mockDriveId, 11),
        null,
      );

      expect(
        await metadataCache.keys,
        [
          'mockDriveId_0',
          'mockDriveId_1',
          'mockDriveId_2',
          'mockDriveId_3',
          'mockDriveId_4',
          'mockDriveId_5',
          'mockDriveId_6',
          'mockDriveId_7',
          'mockDriveId_8',
          'mockDriveId_9',
        ],
      );
    });

    test('can remove added items', () async {
      final metadataCache = await GQLNodesCache.fromCacheStore(
        await newMemoryCacheStore(),
        maxEntries: 10,
      );

      final mockData = generateMockData(10);

      for (int i = 0; i < mockData.length; i++) {
        await metadataCache.put(mockDriveId, mockData[i]);
        expect(await metadataCache.get(mockDriveId, i), mockData[i]);
        await metadataCache.remove(mockDriveId, i);
        expect(await metadataCache.get(mockDriveId, i), null);
      }
    });

    test('can be cleared', () async {
      final metadataCache = await GQLNodesCache.fromCacheStore(
        await newMemoryCacheStore(),
        maxEntries: 10,
      );

      final mockData = generateMockData(10);

      for (int i = 0; i < mockData.length; i++) {
        await metadataCache.put(mockDriveId, mockData[i]);
      }

      final keys = await metadataCache.keys;
      expect(keys, [
        'mockDriveId_0',
        'mockDriveId_1',
        'mockDriveId_2',
        'mockDriveId_3',
        'mockDriveId_4',
        'mockDriveId_5',
        'mockDriveId_6',
        'mockDriveId_7',
        'mockDriveId_8',
        'mockDriveId_9',
      ]);

      await metadataCache.clear();

      final keysAfterClear = await metadataCache.keys;
      expect(keysAfterClear, []);
    });

    test('asSteamOfNodes method returns a stream of nodes', () async {
      final metadataCache = await GQLNodesCache.fromCacheStore(
        await newMemoryCacheStore(),
        maxEntries: 10,
      );

      final streamWhenEmpty = metadataCache.asStreamOfNodes(mockDriveId);
      expect(streamWhenEmpty, emitsDone);

      final mockData = generateMockData(10);

      for (int i = 0; i < mockData.length; i++) {
        await metadataCache.put(mockDriveId, mockData[i]);
      }

      final stream = metadataCache.asStreamOfNodes(mockDriveId);

      expect(
        stream,
        emitsInOrder(
          [
            mockData[0],
            mockData[1],
            mockData[2],
            mockData[3],
            mockData[4],
            mockData[5],
            mockData[6],
            mockData[7],
            mockData[8],
            mockData[9],
          ],
        ),
      );
    });

    test('asStreamOfNodes with ignoreLatestBlock', () async {
      final metadataCache = await GQLNodesCache.fromCacheStore(
        await newMemoryCacheStore(),
        maxEntries: 10,
      );

      final mockData = generateMockData(10);

      for (int i = 0; i < mockData.length; i++) {
        await metadataCache.put(mockDriveId, mockData[i]);
      }

      final stream = metadataCache.asStreamOfNodes(
        mockDriveId,
        ignoreLatestBlock: true,
      );

      expect(
        stream,
        emitsInOrder(
          [
            mockData[0],
            mockData[1],
            mockData[2],
            mockData[3],
            mockData[4],
            mockData[5],
            mockData[6],
            mockData[7],
            mockData[8],
          ],
        ),
      );
    });

    test(
        'range method will return the range of blocks where there is data for a specific drive id',
        () async {
      final metadataCache = await GQLNodesCache.fromCacheStore(
        await newMemoryCacheStore(),
        maxEntries: 10,
      );

      final rangeBefore = await metadataCache.range(mockDriveId);
      expect(rangeBefore.start, -1);
      expect(rangeBefore.end, -1);

      final mockData = generateMockData(10);

      for (int i = 0; i < mockData.length; i++) {
        await metadataCache.put(mockDriveId, mockData[i]);
      }

      final rangeAfter = await metadataCache.range(mockDriveId);
      expect(rangeAfter.start, 0);
      expect(rangeAfter.end, 9);
    });

    test('can add items for many drives', () async {
      final metadataCache = await GQLNodesCache.fromCacheStore(
        await newMemoryCacheStore(),
        maxEntries: 10,
      );

      final mockData = generateMockData(5);

      for (int i = 0; i < mockData.length; i++) {
        await metadataCache.put(mockDriveId, mockData[i]);
        expect(await metadataCache.get(mockDriveId, i), mockData[i]);

        await metadataCache.put(mockDriveId2, mockData[i]);
        expect(await metadataCache.get(mockDriveId2, i), mockData[i]);
      }

      final nextIndexForDriveId1 = await metadataCache.nextIndexForDriveId(
        mockDriveId,
      );
      expect(nextIndexForDriveId1, 5);

      final nextIndexForDriveId2 = await metadataCache.nextIndexForDriveId(
        mockDriveId2,
      );
      expect(nextIndexForDriveId2, 5);
    });

    group('with a stash_shared_preferences cache', () {
      late GQLNodesCache metadataCache;

      setUpAll(() {
        SharedPreferences.setMockInitialValues({});
      });

      test('can be constructed', () async {
        final store = await newSharedPreferencesCacheStore();
        metadataCache = await GQLNodesCache.fromCacheStore(
          store,
          maxEntries: 1,
        );

        expect(metadataCache, isInstanceOf<GQLNodesCache>());
      });

      test('can write and read data', () async {
        final mockItem = newMockItem(0);

        await metadataCache.put(
          'fibonacci',
          mockItem,
        );

        final storedData = await metadataCache.get('fibonacci', 0);
        expect(storedData, mockItem);

        final keys = await metadataCache.keys;
        expect(keys, ['fibonacci_0']);
      });

      test('can recover the previously written index per drive', () async {
        SharedPreferences.setMockInitialValues({
          'gql-nodes-cache_${mockDriveId}_0': Uint8List.fromList([0]),
          'gql-nodes-cache_${mockDriveId}_1': Uint8List.fromList([0]),
          'gql-nodes-cache_${mockDriveId}_2': Uint8List.fromList([0]),
        });

        final store = await newSharedPreferencesCacheStore();
        metadataCache = await GQLNodesCache.fromCacheStore(
          store,
          maxEntries: 3,
        );

        final storedData = await metadataCache.nextIndexForDriveId(mockDriveId);
        expect(storedData, 3);
      });
    });

    group('GQLNodesCacheKeyParts class', () {
      test('can be constructed out of driveId and an index', () {
        final keyParts = GQLNodesCacheKeyParts(mockDriveId, 0);
        expect(keyParts.driveId, mockDriveId);
        expect(keyParts.index, 0);
      });

      test('can be encoded to string', () {
        final keyParts = GQLNodesCacheKeyParts(mockDriveId, 0);
        expect(keyParts.toString(), '${mockDriveId}_0');
      });
    });
  });
}

List<DriveHistoryTransaction> generateMockData(int count) {
  final List<DriveHistoryTransaction> mockData = [];

  for (int i = 0; i < count; i++) {
    mockData.add(newMockItem(i));
  }

  return mockData;
}

DriveHistoryTransaction newMockItem(int index) {
  return DriveHistoryTransaction.fromJson({
    'id': 'mockDriveId_$index',
    'owner': {'address': 'mockOwner_$index'},
    'bundledIn': {'id': 'mockBundledIn_$index'},
    'block': {'height': index, 'timestamp': 100 * index},
    'tags': [],
  });
}
