import 'package:ardrive/utils/key_value_store.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as html;

/// A [KeyValueStore] that lives exactly as long as the browser tab does.
///
/// [LocalKeyValueStore] is backed by `shared_preferences`, which on the web is
/// `localStorage`: it survives the tab, every other tab of the same origin can
/// read it, and nothing ever clears it. That is the correct store for a theme
/// preference and the wrong one for a secret.
///
/// This store is backed by `sessionStorage` instead, which is scoped to one
/// tab and cleared when that tab closes. It exists for the recipient's access
/// key on the shared file page - a key the sender has already sent through at
/// least one chat system - and for nothing else. Never put a wallet, a drive
/// key, or anything the *owner* holds in here.
///
/// `universal_html` rather than `dart:html` so that the mobile build still
/// compiles; off the web its `window` is an in-memory simulation, which gives
/// the desktop and mobile builds process-lifetime semantics - the honest
/// analogue of "while this tab is open".
class SessionKeyValueStore implements KeyValueStore {
  SessionKeyValueStore._(this._storage);

  factory SessionKeyValueStore() {
    try {
      return SessionKeyValueStore._(html.window.sessionStorage);
    } catch (e) {
      // A platform without a session storage of its own falls back to memory
      // that lasts as long as the process, which is never *more* persistent
      // than the tab-scoped storage this class promises.
      logger.w(
        'Session storage is unavailable on this platform; falling back to an '
        'in-memory store for this process. Error: $e',
      );

      return SessionKeyValueStore._(_processMemory);
    }
  }

  /// An in-memory store, for tests and for platforms without session storage.
  @visibleForTesting
  factory SessionKeyValueStore.inMemory([Map<String, String>? storage]) =>
      SessionKeyValueStore._(storage ?? <String, String>{});

  /// `Storage` implements `Map<String, String>`, so one field types both the
  /// real session storage and the in-memory fallback.
  final Map<String, String> _storage;

  static final Map<String, String> _processMemory = <String, String>{};

  @override
  Future<bool> putBool(String key, bool value) async {
    _storage[key] = value.toString();

    return true;
  }

  @override
  bool? getBool(String key) {
    final value = _storage[key];

    return value == null ? null : value == 'true';
  }

  @override
  Future<bool> putString(String key, String value) async {
    _storage[key] = value;

    return true;
  }

  @override
  String? getString(String key) => _storage[key];

  @override
  Future<bool> remove(String key) async {
    _storage.remove(key);

    return true;
  }

  @override
  Set<String> getKeys() => _storage.keys.toSet();
}
