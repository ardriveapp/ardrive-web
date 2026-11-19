import 'package:ardrive/utils/key_value_store.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/session_key_value_store.dart';
import 'package:ardrive/utils/shared_file_link.dart';

/// Holds a recipient's access key for as long as their tab is open.
///
/// Opt-in only: nothing is written unless the recipient ticks "Remember while
/// this tab is open" on the locked gate (review §4.5). The store underneath is
/// `sessionStorage` - never `localStorage`, never a cookie - so closing the tab
/// forgets the key, and no other tab can read it.
///
/// A key that turns out not to work is forgotten immediately: a stale key that
/// keeps re-submitting itself would strand the recipient behind an error they
/// cannot clear.
///
/// A private drive or folder page keeps its publication key the same way,
/// under its own [prefix] and by publication ID ([SharedFileKeySession.page]).
class SharedFileKeySession {
  SharedFileKeySession({KeyValueStore? store})
      : _store = store ?? SessionKeyValueStore(),
        _prefix = filePrefix;

  /// A private page's publication key, for this tab.
  SharedFileKeySession.page({KeyValueStore? store})
      : _store = store ?? SessionKeyValueStore(),
        _prefix = pagePrefix;

  static const filePrefix = 'sharedFileAccessKey';
  static const pagePrefix = 'publicationKey';

  final KeyValueStore _store;
  final String _prefix;

  /// Namespaced by file so that opening a second shared link in the same tab
  /// never offers the first file's key.
  static String storageKey(String fileId) => '$filePrefix.$fileId';

  String _keyOf(String id) => '$_prefix.$id';

  /// The remembered key for [fileId], or `null` when there is none to use.
  ///
  /// Anything that is not a well formed key is dropped rather than handed to
  /// the cubit: it can only fail, and it would fail as a *wrong key* error the
  /// recipient never typed.
  Future<String?> read(String fileId) async {
    try {
      final value = await _store.getString(_keyOf(fileId));

      if (value == null || !SharedFileLinkKey.isWellFormed(value)) {
        return null;
      }

      return value;
    } catch (e) {
      logger.w('Failed to read the remembered access key. Error: $e');

      return null;
    }
  }

  /// Remembers [rawKey] for [fileId] until the tab closes.
  Future<void> remember(String fileId, String rawKey) async {
    if (!SharedFileLinkKey.isWellFormed(rawKey)) {
      return;
    }

    try {
      await _store.putString(_keyOf(fileId), rawKey);
    } catch (e) {
      // Never surfaced: failing to remember a key is a convenience the
      // recipient loses, not an error they can act on.
      logger.w('Failed to remember the access key for this tab. Error: $e');
    }
  }

  /// Forgets any key remembered for [fileId].
  Future<void> forget(String fileId) async {
    try {
      await _store.remove(_keyOf(fileId));
    } catch (e) {
      logger.w('Failed to forget the remembered access key. Error: $e');
    }
  }
}
