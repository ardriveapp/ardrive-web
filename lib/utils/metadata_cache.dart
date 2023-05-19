import 'dart:typed_data';

import 'package:ardrive/utils/logger/logger.dart';
import 'package:stash/stash_api.dart';

const defaultMaxEntries = 20000;
const defaultCacheName = 'metadata-cache';

class MetadataCache {
  final Cache<Uint8List> _cache;

  const MetadataCache(this._cache);

  Future<void> put(String key, Uint8List data) async {
    logger.d('Putting $key in cache');
    return _cache.put(key, data);
  }

  Future<Uint8List?> get(String key) async {
    final value = await _cache.get(key);
    if (value != null) {
      logger.d('Cache hit for $key');
    } else {
      logger.d('Cache miss for $key');
    }
    return value;
  }

  Future<void> remove(String key) async {
    return _cache.remove(key);
  }

  Future<void> clear() async {
    return _cache.clear();
  }

  Future<Iterable<String>> get keys async {
    return _cache.keys;
  }

  static Future<Cache<Uint8List>> newCacheFromStore(
    CacheStore store, {
    int maxEntries = defaultMaxEntries,
  }) {
    return store.cache<Uint8List>(
      name: defaultCacheName,
      maxEntries: maxEntries,
      evictionPolicy: const LfuEvictionPolicy(),
    );
  }
}
