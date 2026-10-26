import 'dart:convert';

import 'package:ardrive/utils/key_value_store.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';

/// Where Turbo ArNS actions not yet finished are kept, one key per ArDrive
/// profile.
const arnsPendingActionsStoragePrefix = 'arnsPendingActions_v1_';

/// A Turbo ArNS action that was created, so already charged, and not yet
/// seen to finish (docs/NAMES.md, "Writes", steps 3 and 6). Kept so a reload
/// can say what became of it. Never used to create the action again.
class ArNSPendingAction extends Equatable {
  const ArNSPendingAction({
    required this.nonce,
    required this.paymentUrl,
    required this.name,
    required this.description,
    required this.createdAt,
  });

  /// Turbo's idempotency key, to read the action's status.
  final String nonce;

  /// The payment service that holds the action: the sandbox on devnet.
  final String paymentUrl;

  /// The literal name it changes: `blog_ardrive`, or `ardrive`.
  final String name;

  /// What it does, for the log: `set-record blog_ardrive -> <txId>`.
  final String description;
  final DateTime createdAt;

  Map<String, Object> toJson() => {
        'nonce': nonce,
        'paymentUrl': paymentUrl,
        'name': name,
        'description': description,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  static ArNSPendingAction? fromJson(Object? json) {
    if (json is! Map) return null;
    final nonce = json['nonce'];
    final paymentUrl = json['paymentUrl'];
    final name = json['name'];
    final createdAt = DateTime.tryParse('${json['createdAt']}');
    if (nonce is! String || paymentUrl is! String || name is! String) {
      return null;
    }
    return ArNSPendingAction(
      nonce: nonce,
      paymentUrl: paymentUrl,
      name: name,
      description: json['description'] as String? ?? '',
      createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  List<Object?> get props => [nonce, paymentUrl, name, description, createdAt];
}

/// Remembers each profile's unfinished Turbo ArNS actions in local storage,
/// as [ArNSWalletStore] remembers its ArNS wallet. Nonces only: nothing here
/// can sign or pay.
class ArNSPendingActionStore {
  ArNSPendingActionStore({Future<KeyValueStore> Function()? openStore})
      : _openStore = openStore ?? LocalKeyValueStore.getInstance;

  final Future<KeyValueStore> Function() _openStore;

  static String _key(String profileAddress) =>
      '$arnsPendingActionsStoragePrefix$profileAddress';

  Future<List<ArNSPendingAction>> pending(String profileAddress) async {
    final store = await _openStore();
    final source = await store.getString(_key(profileAddress));
    if (source == null) return [];
    try {
      final json = jsonDecode(source);
      if (json is! List) return [];
      return [
        for (final entry in json)
          if (ArNSPendingAction.fromJson(entry) case final action?) action,
      ];
    } catch (_) {
      return [];
    }
  }

  /// Remembers [action], replacing one with the same nonce.
  Future<void> add(String profileAddress, ArNSPendingAction action) async {
    final actions = [
      for (final a in await pending(profileAddress))
        if (a.nonce != action.nonce) a,
      action,
    ];
    await _write(profileAddress, actions);
  }

  /// Forgets the action with [nonce], once it reached an end.
  Future<void> remove(String profileAddress, String nonce) async {
    final before = await pending(profileAddress);
    final actions = [
      for (final a in before)
        if (a.nonce != nonce) a,
    ];
    if (actions.length == before.length) return;
    await _write(profileAddress, actions);
  }

  Future<void> _write(
    String profileAddress,
    List<ArNSPendingAction> actions,
  ) async {
    final store = await _openStore();
    if (actions.isEmpty) {
      await store.remove(_key(profileAddress));
      return;
    }
    await store.putString(
      _key(profileAddress),
      jsonEncode([for (final a in actions) a.toJson()]),
    );
  }

  /// Forgets every profile's actions, at sign-out.
  Future<void> clear() async {
    try {
      final store = await _openStore();
      for (final key in await store.getKeys()) {
        if (key.startsWith(arnsPendingActionsStoragePrefix)) {
          await store.remove(key);
        }
      }
    } catch (e) {
      logger.w('Could not clear the pending ArNS actions: $e');
    }
  }
}
