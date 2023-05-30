import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:stash/stash_api.dart';

const defaultMaxEntries = 20000;
const defaultCacheName = 'gql-nodes-cache';

// TODO: PE-2782: Abstract auto-generated GQL types
typedef DriveHistoryTransaction
    = DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction;

class GQLNodesCache {
  final Cache<DriveHistoryTransaction> _cache;
  final int _maxEntries;
  Map<String, int>? _nextIndexForDriveId;

  GQLNodesCache(this._cache, {int maxEntries = defaultMaxEntries})
      : _maxEntries = maxEntries;

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

  Future<bool> put(String driveId, DriveHistoryTransaction data) async {
    if (await isFull) {
      return false;
    }

    final nextIndex = await nextIndexForDriveId(driveId);
    final key = '${driveId}_$nextIndex';

    logger.d('Putting $key in GQL Nodes cache');
    await _cache.put(key, data).then(
          (value) => _nextIndexForDriveId![driveId] = nextIndex,
        );

    if (await isFull) {
      logger.i('GQL Nodes cache is now full and will not accept new entries');
    }

    return true;
  }

  Future<DriveHistoryTransaction?> get(String driveId, int index) async {
    final key = '${driveId}_$index';
    final value = await _cache.get(key);
    if (value != null) {
      logger.d('Cache hit for $key in GQL Nodes cache');
    } else {
      logger.d('Cache miss for $key in GQL Nodes cache');
    }
    return value;
  }

  Future<void> remove(String driveId, int index) async {
    final key = '${driveId}_$index';
    logger.d('Removing $key from GQL Nodes cache');
    return _cache.remove(key);
  }

  Future<void> clear() async {
    logger.d('Clearing GQL Nodes cache');
    return _cache.clear();
  }

  Future<Iterable<String>> get keys async {
    return _cache.keys;
  }

  Future<bool> get isFull async {
    final size = await this.size;
    final isFull = size >= _maxEntries;

    return isFull;
  }

  Future<int> get size async {
    return _cache.size;
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
