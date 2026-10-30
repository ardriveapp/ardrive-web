import 'package:ardrive/utils/key_value_store.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive/utils/logger.dart';

/// Remembers on this device, per wallet address, that the password it signs
/// in with didn't open any of its private drives - the user continued past
/// "This password didn't open your private drives" - so the next visit,
/// which unlocks the profile without trying any drive (Welcome back,
/// biometrics), still knows.
///
/// Only that fact: no password, no key. A per-device preference like the
/// others in the local key-value store, deliberately not a profile column
/// (the profile is changing in another piece of work).
class SignInPasswordProofStore {
  SignInPasswordProofStore({Future<KeyValueStore> Function()? store})
      : _store = store ?? LocalKeyValueStore.getInstance;

  final Future<KeyValueStore> Function() _store;

  static String _key(String address) => 'signInPasswordUnproven_$address';

  /// Whether this device recorded [address]'s sign-in password as unproven.
  Future<bool> isUnproven(String address) async {
    try {
      final unproven = await (await _store()).getBool(_key(address));
      return unproven ?? false;
    } catch (e) {
      logger.w('Could not read whether the sign-in password was proven: $e');
      return false;
    }
  }

  Future<void> markUnproven(String address) async {
    try {
      await (await _store()).putBool(_key(address), true);
    } catch (e) {
      logger.w('Could not record an unproven sign-in password: $e');
    }
  }

  /// Forgets it: the password was proven, or the user signed out.
  Future<void> clear(String address) async {
    try {
      await (await _store()).remove(_key(address));
    } catch (e) {
      logger.w('Could not clear the sign-in password record: $e');
    }
  }
}
