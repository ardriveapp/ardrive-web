import 'package:ardrive/utils/key_value_store.dart';

/// What the last start found on this device: an account, or none.
enum ProfilePresence {
  /// Nothing recorded, though the app has run here before: the hint
  /// predates this device's last start, or was removed on its own.
  unknown,
  present,
  absent,
}

/// Remembers whether this device holds an account, so the next start can
/// draw the right sign-in panel (Welcome back, or the landing) while the
/// database is still opening, instead of a blank page.
///
/// A hint and no more: the database says what is true, and the panel only
/// becomes usable once it has. [ProfileCubit] writes it whenever it learns
/// the answer, so a wrong hint lasts one start at most.
class ProfilePresenceHint {
  /// Reads the hint now, so build it before anything writes to [store] at
  /// startup: a store with nothing in it at all is a browser that has never
  /// run the app, which holds no account.
  ProfilePresenceHint(this._store) : atStart = _read(_store);

  final KeyValueStore _store;

  /// The hint as it was when this start began.
  final ProfilePresence atStart;

  static const storageKey = 'profilePresence';

  /// Synchronous, for the first frame: a store that answers later (none
  /// does on the web) reads as [ProfilePresence.unknown].
  static ProfilePresence _read(KeyValueStore store) {
    try {
      final recorded = store.getBool(storageKey);
      if (recorded is bool) {
        return recorded ? ProfilePresence.present : ProfilePresence.absent;
      }
      final keys = store.getKeys();
      if (recorded == null && keys is Set<String> && keys.isEmpty) {
        return ProfilePresence.absent;
      }
      return ProfilePresence.unknown;
    } catch (_) {
      return ProfilePresence.unknown;
    }
  }

  Future<void> record({required bool present}) async {
    try {
      if (await _store.getBool(storageKey) == present) return;
      await _store.putBool(storageKey, present);
    } catch (_) {
      // A hint that can't be stored costs one neutral panel, nothing more.
    }
  }
}
