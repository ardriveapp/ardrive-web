import 'package:ardrive/utils/key_value_store.dart';
import 'package:ardrive/utils/local_key_value_store.dart';

/// What a new account's first drive is called.
const firstDriveName = 'My files';

/// Carries a new account's first drive from sign-up into the app, where it is
/// made: a private "My files", so the first thing a new user sees is a place
/// for their files rather than a choice between kinds of drive.
///
/// Kept in local storage so a reload between the two still makes the drive,
/// and kept for one wallet so it is only ever made for the account that just
/// signed up.
class FirstDrive {
  FirstDrive({Future<KeyValueStore> Function()? openStore})
      : _openStore = openStore ?? LocalKeyValueStore.getInstance;

  static const _key = 'firstDrivePendingFor';

  final Future<KeyValueStore> Function() _openStore;

  /// Asks for [walletAddress]'s first drive to be made when it reaches the
  /// app.
  Future<void> request(String walletAddress) async {
    await (await _openStore()).putString(_key, walletAddress);
  }

  /// Whether [walletAddress] is owed its first drive. True at most once:
  /// asking spends the request, so a failed attempt is never retried into a
  /// second drive.
  Future<bool> claim(String walletAddress) async {
    final store = await _openStore();
    // Read and spent with no await between, so two claims at once can't
    // both win (the local store reads synchronously).
    final read = store.getString(_key);
    final pendingFor = read is Future<String?> ? await read : read;

    if (pendingFor == null) return false;

    await store.remove(_key);
    return pendingFor == walletAddress;
  }
}
