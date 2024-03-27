import 'dart:typed_data';

import 'package:ardrive/utils/logger.dart';
import 'package:stash/stash_api.dart';

const defaultMaxEntries = 550;
const defaultCacheName = 'metadata-cache';

class MetadataCache {
  final Cache<Uint8List> _cache;
  final int _maxEntries;

  MetadataCache(this._cache, {int maxEntries = defaultMaxEntries})
      : _maxEntries = maxEntries;

  static Future<MetadataCache> fromCacheStore(
    CacheStore store, {
    int maxEntries = defaultMaxEntries,
  }) async {
    final cache = await _newCacheFromStore(store, maxEntries: maxEntries);
    return MetadataCache(cache, maxEntries: maxEntries);
  }

  Future<bool> put(String key, Uint8List data) async {
    if (await isFull) {
      return false;
    }

    // FIXME: check for quota before attempting to write to cache
    try {
      await _cache.putIfAbsent(key, data);
    } catch (e, s) {
      logger.e('Failed to put $key in metadata cache', e, s);
      return false;
    }

    if (await isFull) {
      logger.i('Metadata cache is now full and will not accept new entries');
    }

    return true;
  }

  Future<Uint8List?> get(String key) async {
    try {
      final value = await _cache.get(key);

      return value;
    } catch (e, s) {
      logger.e('Failed to get $key from metadata cache', e, s);
      return null;
    }
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

    return isFull;
  }

  Future<int> get size async {
    return _cache.size;
  }

  static Future<Cache<Uint8List>> _newCacheFromStore(
    CacheStore store, {
    required int maxEntries,
  }) async {
    return store.cache<Uint8List>(
      name: defaultCacheName,
      maxEntries: maxEntries,

      // See: https://pub.dev/packages/stash#eviction-policies
      evictionPolicy: null,
    );
  }
}
