import 'package:ardrive/utils/key_value_store.dart';
import 'package:ardrive/utils/local_key_value_store.dart';

/// What a new account's first drive is called.
const firstDriveName = 'My files';

/// Carries a new account's first drive from sign-up into the app, where it is
/// made: a private "My files", so the first thing a new user sees is a place
/// for their files rather than a choice between kinds of drive.
///
/// Kept in local storage so a reload, or Turbo being away for a while, still
/// ends with the drive made; kept for one wallet so it is only ever made for
/// the account that signed up; and dropped after a day, so an account that
/// never got it, or has made drives of its own since, never has one appear
/// later.
///
/// Stored as `address|requested`, or `address|requested|leased` while one
/// attempt is under way, so a second tab waits rather than making another.
class FirstDrive {
  FirstDrive({
    Future<KeyValueStore> Function()? openStore,
    DateTime Function()? now,
  })  : _openStore = openStore ?? LocalKeyValueStore.getInstance,
        _now = now ?? DateTime.now;

  static const _key = 'firstDrivePendingFor';

  /// How long a request is honoured.
  static const requestLifetime = Duration(days: 1);

  /// How long one attempt holds the request before another may take it.
  static const leaseLifetime = Duration(minutes: 2);

  final Future<KeyValueStore> Function() _openStore;
  final DateTime Function() _now;

  /// Asks for [walletAddress]'s first drive to be made when it reaches the
  /// app.
  Future<void> request(String walletAddress) async {
    final now = _now().millisecondsSinceEpoch;
    await (await _openStore()).putString(_key, '$walletAddress|$now');
  }

  /// Whether [walletAddress] is owed its first drive now. On true the caller
  /// holds it and ends with [done] or [release]; until then, or until the
  /// hold lapses, no other claim succeeds. A request for another wallet, or
  /// an expired one, is dropped.
  Future<bool> claim(String walletAddress) async {
    final store = await _openStore();
    // Read and held with no await between, so two claims at once can't both
    // win (the local store reads and writes its cache synchronously).
    final read = store.getString(_key);
    final stored = read is Future<String?> ? await read : read;
    if (stored == null) return false;

    final parts = stored.split('|');
    final requested = parts.length > 1 ? int.tryParse(parts[1]) : null;
    final leased = parts.length > 2 ? int.tryParse(parts[2]) : null;
    final now = _now().millisecondsSinceEpoch;

    final expired =
        requested == null || now - requested > requestLifetime.inMilliseconds;
    if (parts.first != walletAddress || expired) {
      await store.remove(_key);
      return false;
    }

    if (leased != null && now - leased < leaseLifetime.inMilliseconds) {
      return false;
    }

    await store.putString(_key, '$walletAddress|$requested|$now');
    return true;
  }

  /// The drive was made, or never can be: the request is spent.
  Future<void> done() async {
    await (await _openStore()).remove(_key);
  }

  /// The attempt failed for now; the next claim may try again.
  Future<void> release(String walletAddress) async {
    final store = await _openStore();
    final read = store.getString(_key);
    final stored = read is Future<String?> ? await read : read;
    final parts = stored?.split('|');
    if (parts == null || parts.length < 2 || parts.first != walletAddress) {
      return;
    }
    await store.putString(_key, '${parts[0]}|${parts[1]}');
  }
}
