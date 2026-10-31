import 'dart:async';

import 'package:ardrive/billing/data/purchase.dart';
import 'package:ardrive/user/user.dart';

/// The purchases a signed-in account has loaded, kept for the session only.
///
/// Memory only, never stored: it is cleared when the account signs out or a
/// different wallet signs in, so the next person at this browser never sees
/// it. Entries are keyed by wallet address as well, so a result can only be
/// read back by the wallet that asked for it.
class BillingSessionCache {
  BillingSessionCache({Stream<User?>? authChanges}) {
    _subscription = authChanges?.listen((user) {
      if (user == null || user.walletAddress != _address) clear();
    });
  }

  StreamSubscription<User?>? _subscription;
  String? _address;
  List<Purchase> _purchases = const [];
  String? _cursor;
  bool _hasMore = false;

  bool hasPurchasesFor(String address) => _address == address;

  List<Purchase> purchasesFor(String address) =>
      _address == address ? _purchases : const [];

  String? cursorFor(String address) => _address == address ? _cursor : null;

  bool hasMoreFor(String address) => _address == address && _hasMore;

  void storePurchases(
    String address, {
    required List<Purchase> purchases,
    required String? cursor,
    required bool hasMore,
  }) {
    _address = address;
    _purchases = List.unmodifiable(purchases);
    _cursor = cursor;
    _hasMore = hasMore;
  }

  void clear() {
    _address = null;
    _purchases = const [];
    _cursor = null;
    _hasMore = false;
  }

  Future<void> dispose() async => _subscription?.cancel();
}
