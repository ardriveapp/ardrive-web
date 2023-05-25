import 'dart:typed_data';

import 'package:ardrive/utils/logger/logger.dart';
import 'package:stash/stash_api.dart';

const defaultMaxEntries = 20000;
const defaultCacheName = 'metadata-cache';

class MetadataCache {
  final Cache<Uint8List> _cache;
  final int _maxEntries;

  const MetadataCache(this._cache, {int maxEntries = defaultMaxEntries})
      : _maxEntries = maxEntries;

  static Future<MetadataCache> fromCacheStore(
    CacheStore store, {
    int maxEntries = defaultMaxEntries,
  }) async {
    final cache = await _newCacheFromStore(store, maxEntries: maxEntries);
    return MetadataCache(cache, maxEntries: maxEntries);
  }

  Future<bool> put(String key, Uint8List data) async {
    final isFull = await this.isFull;
    if (isFull) {
      logger.d('Cache is full, not putting $key in metadata cache');
      return false;
    }

    logger.d('Putting $key in metadata cache');
    await _cache.put(key, data);
    return true;
  }

  Future<Uint8List?> get(String key) async {
    final value = await _cache.get(key);
    if (value != null) {
      logger.d('Cache hit for $key in metadata cache');
    } else {
      logger.d('Cache miss for $key in metadata cache');
    }
    return value;
  }

  Future<void> remove(String key) async {
    logger.d('Removing $key from metadata cache');
    return _cache.remove(key);
  }

  Future<void> clear() async {
    logger.d('Clearing metadata cache');
    return _cache.clear();
  }

  Future<Iterable<String>> get keys async {
    return _cache.keys;
  }

  Future<bool> get isFull async {
    final size = await this.size;
    final isFull = size >= _maxEntries;
    logger.d('Cache is full: $isFull - size: $size, max: $defaultMaxEntries');
    return isFull;
  }

  Future<int> get size async {
    return _cache.size;
  }

  static Future<Cache<Uint8List>> _newCacheFromStore(
    CacheStore store, {
    required int maxEntries,
  }) async {
    logger.d('Creating metadata cache with max entries: $maxEntries');

    return store.cache<Uint8List>(
      name: defaultCacheName,
      maxEntries: maxEntries,

      // See: https://pub.dev/packages/stash#eviction-policies
      evictionPolicy: null,
    );
  }
}
