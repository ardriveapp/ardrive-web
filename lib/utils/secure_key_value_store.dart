import 'dart:async';

import 'package:ardrive/utils/key_value_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  FutureOr<bool?> getBool(String key) async {
    final booleanString = await _storage.read(key: key);

    if (booleanString == null) {
      return null;
    }

    if (booleanString != 'true' && booleanString != 'false') {
      throw Exception('The value for its $key is not a boolean type.');
    }

    return booleanString == 'true' ? true : false;
  }

  @override
  Future<Set<String>> getKeys() async {
    final allData = await _storage.readAll();

    return Set.from(allData.keys);
  }

  @override
  Future<String?> getString(String key) async {
    return _storage.read(key: key);
  }

  @override
  Future<bool> putBool(String key, bool value) async {
    await _storage.write(key: key, value: value.toString());
    return true;
  }

  @override
  Future<bool> putString(String key, String value) async {
    await _storage.write(key: key, value: value);
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    await _storage.delete(key: key);
    return true;
  }
}
