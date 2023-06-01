import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:stash/stash_api.dart';

const defaultMaxEntries = 2000;
const defaultCacheName = 'gql-nodes-cache';

// TODO: PE-2782: Abstract auto-generated GQL types
typedef DriveHistoryTransaction
    = DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction;

class GQLNodesCache {
  final Cache<DriveHistoryTransaction> _persistingCache;
  final int _maxEntries;
  Map<String, int>? _nextIndexForDriveId;

  GQLNodesCache(
    this._persistingCache, {
    int maxEntries = defaultMaxEntries,
  }) : _maxEntries = maxEntries;

  static Future<GQLNodesCache> fromCacheStore(
    CacheStore store, {
    int maxEntries = defaultMaxEntries,
  }) async {
    final cache = await _newCacheFromStore(store, maxEntries: maxEntries);
    return GQLNodesCache(cache, maxEntries: maxEntries);
  }

  static Future<Cache<DriveHistoryTransaction>> _newCacheFromStore(
    CacheStore store, {
    required int maxEntries,
  }) async {
    logger.d('Creating GQL Nodes cache with max entries: $maxEntries');

    return store.cache<DriveHistoryTransaction>(
      name: defaultCacheName,
      maxEntries: maxEntries,
      fromEncodable: DriveHistoryTransaction.fromJson,

      // See: https://pub.dev/packages/stash#eviction-policies
      evictionPolicy: null,
    );
  }

  Future<Range> range(DriveID driveId) async {
    final keys = await _persistingCache.keys;
    final keysForDriveId = keys.where((key) => key.startsWith(driveId));
    if (keysForDriveId.isEmpty) {
      return Range.nullRange;
    }

    final sortedKeysForDriveId = keysForDriveId.toList()
      ..sort(
        (a, b) {
          final indexRegexp = RegExp(r'.+_(\d+)$');
          final aIndex = int.parse(indexRegexp.firstMatch(a)!.group(1)!);
          final bIndex = int.parse(indexRegexp.firstMatch(b)!.group(1)!);
          return aIndex.compareTo(bIndex);
        },
      );

    final lastKey = sortedKeysForDriveId.last;
    final lastValue = (await _persistingCache.get(lastKey))!;

    const firstBlock = 0; // Always from genesis
    final lastBlock = lastValue.block!.height;

    return Range(start: firstBlock, end: lastBlock);
  }

  Stream<DriveHistoryTransaction> asStreamOfNodes(
    String driveId, {
    bool ignoreLatestBlock = false,
  }) async* {
    final keys = await _persistingCache.keys;
    final keysForDriveId = keys.where((key) => key.startsWith(driveId));
    final sortedKeysForDriveId = keysForDriveId.toList()
      ..sort(
        (a, b) {
          final indexRegexp = RegExp(r'.+_(\d+)$');
          final aIndex = int.parse(indexRegexp.firstMatch(a)!.group(1)!);
          final bIndex = int.parse(indexRegexp.firstMatch(b)!.group(1)!);
          return aIndex.compareTo(bIndex);
        },
      );

    if (ignoreLatestBlock && sortedKeysForDriveId.isNotEmpty) {
      logger.d('Asked to ignore latest block');
      final latestItem = sortedKeysForDriveId.last;
      final latestBlockHeight = (await _forceGet(latestItem)).block!.height;
      bool hasReadAllItemsOnLatestBlock = false;
      while (!hasReadAllItemsOnLatestBlock && sortedKeysForDriveId.isNotEmpty) {
        final cacheKey = sortedKeysForDriveId.removeLast();
        final blockHeight = (await _forceGet(cacheKey)).block!.height;
        logger.d(
            'Checking if $cacheKey is on latest block. Latest block: $latestBlockHeight, block of $cacheKey: $blockHeight');
        if (blockHeight != latestBlockHeight) {
          sortedKeysForDriveId.add(cacheKey); // add it back
          hasReadAllItemsOnLatestBlock = true;
        }
      }
      logger.d('Done ignoring latest block');
    }

    logger.d(
      'There are ${sortedKeysForDriveId.length} items in cache to be streamed',
    );

    yield* Stream.fromFutures(
      sortedKeysForDriveId.map(
        (key) => _forceGet(key),
      ),
    );
  }

  Future<bool> put(String driveId, DriveHistoryTransaction data) async {
    if (await isFull) {
      return false;
    }

    final nextIndex = await nextIndexForDriveId(driveId);
    final key = '${driveId}_$nextIndex';

    // FIXME: check for quota before attempting to write to cache
    try {
      logger.d('Putting $key in GQL Nodes cache');
      await _persistingCache.putIfAbsent(key, data);
      _nextIndexForDriveId![driveId] = nextIndex;
    } catch (e, s) {
      logger.e('Failed to put $key in GQL Nodes cache', e, s);
      return false;
    }

    if (await isFull) {
      logger.i('GQL Nodes cache is now full and will not accept new entries');
    }

    return true;
  }

  Future<DriveHistoryTransaction> _forceGet(String key) async {
    logger.d('Asked to force get $key from GQL Nodes cache');
    final maybeValue = await _persistingCache.get(key);
    if (maybeValue == null) {
      logger.e('Could not find $key in GQL Nodes cache');
      throw Exception('Could not find $key in GQL Nodes cache');
    }
    return maybeValue;
  }

  Future<DriveHistoryTransaction?> get(String driveId, int index) async {
    final key = '${driveId}_$index';
    try {
      final value = await _persistingCache.get(key);
      if (value != null) {
        logger.d('Cache hit for $key in GQL Nodes cache');
      } else {
        logger.d('Cache miss for $key in GQL Nodes cache');
      }
      return value;
    } catch (e, s) {
      logger.e('Failed to get $key from GQL Nodes cache', e, s);
      return null;
    }
  }

  Future<void> remove(String driveId, int index) async {
    final key = '${driveId}_$index';
    logger.d('Removing $key from GQL Nodes cache');
    return _persistingCache.remove(key);
  }

  Future<void> clear() async {
    logger.d('Clearing GQL Nodes cache');
    return _persistingCache.clear();
  }

  Future<Iterable<String>> get keys async {
    return _persistingCache.keys;
  }

  Future<bool> get isFull async {
    final size = await this.size;
    final isFull = size >= _maxEntries;

    return isFull;
  }

  Future<int> get size async {
    return _persistingCache.size;
  }

  Future<int> nextIndexForDriveId(String driveId) async {
    _nextIndexForDriveId ??= await currentIndexesPerDriveId;

    if (_nextIndexForDriveId![driveId] == null) {
      // There are no entries for this driveId yet
      _nextIndexForDriveId![driveId] = -1;
    }

    final nextIndex = _nextIndexForDriveId![driveId]! + 1;
    return nextIndex;
  }

  Future<Map<String, int>> get currentIndexesPerDriveId async {
    final Map<String, int> currentIndexesPerDriveId = {};

    final regexp = RegExp(r'^(.+)_(\d+)$');

    final keys = await this.keys;
    for (final key in keys) {
      final match = regexp.firstMatch(key)!;
      final driveId = match.group(1)!;
      final index = int.parse(match.group(2)!);

      if (currentIndexesPerDriveId[driveId] == null ||
          currentIndexesPerDriveId[driveId]! < index) {
        currentIndexesPerDriveId[driveId] = index;
      }
    }

    return currentIndexesPerDriveId;
  }
}
