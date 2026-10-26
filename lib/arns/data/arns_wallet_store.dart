import 'dart:convert';

import 'package:ardrive/utils/key_value_store.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';

/// Where linked ArNS wallets are kept, one key per ArDrive profile.
const arnsWalletStoragePrefix = 'arnsWallet_v1_';

/// The Solana wallet linked to approve name changes for one profile.
class LinkedArNSWallet extends Equatable {
  const LinkedArNSWallet({required this.address, this.walletName});

  final String address;

  /// The Wallet Standard name it was linked with, to reconnect silently.
  /// Null for a Solana sign-in, linked without a connection.
  final String? walletName;

  String toJson() => jsonEncode({
        'address': address,
        if (walletName != null) 'walletName': walletName,
      });

  static LinkedArNSWallet? fromJson(String? source) {
    if (source == null) return null;
    try {
      final json = jsonDecode(source) as Map<String, dynamic>;
      return LinkedArNSWallet(
        address: json['address'] as String,
        walletName: json['walletName'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  List<Object?> get props => [address, walletName];
}

/// Remembers the linked ArNS wallet per profile, so names can be read with no
/// live connection (docs/NAMES.md, "Wallets and paying"). An address only:
/// nothing here can sign.
class ArNSWalletStore {
  ArNSWalletStore({Future<KeyValueStore> Function()? openStore})
      : _openStore = openStore ?? LocalKeyValueStore.getInstance;

  final Future<KeyValueStore> Function() _openStore;

  static String _key(String profileAddress) =>
      '$arnsWalletStoragePrefix$profileAddress';

  Future<LinkedArNSWallet?> linked(String profileAddress) async {
    final store = await _openStore();
    return LinkedArNSWallet.fromJson(
      await store.getString(_key(profileAddress)),
    );
  }

  Future<void> link(String profileAddress, LinkedArNSWallet wallet) async {
    final store = await _openStore();
    await store.putString(_key(profileAddress), wallet.toJson());
  }

  Future<void> unlink(String profileAddress) async {
    final store = await _openStore();
    await store.remove(_key(profileAddress));
  }

  /// Forgets every profile's ArNS wallet, at sign-out.
  Future<void> clear() async {
    try {
      final store = await _openStore();
      for (final key in await store.getKeys()) {
        if (key.startsWith(arnsWalletStoragePrefix)) {
          await store.remove(key);
        }
      }
    } catch (e) {
      logger.w('Could not clear the linked ArNS wallets: $e');
    }
  }
}
