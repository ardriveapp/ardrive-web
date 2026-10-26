import 'dart:async';

import 'package:ardrive/arns/data/arns_wallet_store.dart';
import 'package:ardrive/arns/data/bridge_arns_owner_signer.dart';
import 'package:ardrive/arns/data/turbo_arns_action_client.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'arns_wallet_state.dart';

/// The ArNS wallet: linked once per profile and remembered, connected only
/// when a change needs approving (docs/NAMES.md, "Wallets and paying").
///
/// Does nothing while names are off.
class ArNSWalletCubit extends Cubit<ArNSWalletState> {
  ArNSWalletCubit({
    required ArioSDK arioSDK,
    required ArNSWalletStore store,
    required ArDriveAuth auth,
    required bool Function() isEnabled,
  })  : _arioSDK = arioSDK,
        _store = store,
        _isEnabled = isEnabled,
        super(const ArNSWalletState()) {
    if (!isEnabled()) return;

    emit(state.copyWith(
      enabled: true,
      installedWallets: _arioSDK.listSolanaWallets(),
    ));
    _subscriptions.addAll([
      _arioSDK.solanaWalletsChanges
          .listen((wallets) => emit(state.copyWith(installedWallets: wallets))),
      _arioSDK.solanaAccountChanges.listen((address) => emit(state.copyWith(
            connectedAddress: () => address,
            connectedWalletName: () =>
                address == null ? null : _arioSDK.connectedSolanaWalletName,
          ))),
      auth.onAuthStateChanged().listen(_onUser),
    ]);

    User? current;
    try {
      current = auth.currentUser;
    } catch (_) {
      // Nobody signed in yet.
    }
    if (current != null) _onUser(current);
  }

  final ArioSDK _arioSDK;
  final ArNSWalletStore _store;
  final bool Function() _isEnabled;
  final _subscriptions = <StreamSubscription>[];

  Future<void> _onUser(User? user) async {
    if (user == null) {
      emit(ArNSWalletState(
        enabled: _isEnabled(),
        installedWallets: state.installedWallets,
      ));
      return;
    }
    if (user.walletAddress == state.profileAddress) return;

    var linked = await _store.linked(user.walletAddress);
    final source = user.sourceWalletAddress;
    // Signed in with Solana: that wallet is the ArNS wallet already.
    if (linked == null &&
        source != null &&
        walletTypeOfSourceAddress(source) == WalletType.solana) {
      linked = LinkedArNSWallet(address: source);
      await _store.link(user.walletAddress, linked);
    }
    if (isClosed) return;

    emit(state.copyWith(
      profileAddress: () => user.walletAddress,
      linked: () => linked,
      connectedAddress: () => _arioSDK.connectedSolanaAddress,
      connectedWalletName: () => _arioSDK.connectedSolanaWalletName,
    ));

    final walletName = linked?.walletName;
    if (walletName != null && state.connectedAddress == null) {
      await _connect(walletName, silent: true);
    }
  }

  /// Links the named wallet as this profile's ArNS wallet, connecting it.
  /// Also how the ArNS wallet is changed.
  Future<void> link(String walletName) async {
    final profile = state.profileAddress;
    if (profile == null || !state.enabled) return;

    final address = await _connect(walletName, silent: false);
    if (address == null) return;

    final linked = LinkedArNSWallet(address: address, walletName: walletName);
    await _store.link(profile, linked);
    if (!isClosed) emit(state.copyWith(linked: () => linked));
  }

  /// Connects the linked wallet again. [walletName] picks the wallet when
  /// none is remembered (a Solana sign-in); it is remembered once it
  /// connects on the linked account.
  Future<void> reconnect({String? walletName}) async {
    final profile = state.profileAddress;
    final linked = state.linked;
    final name = walletName ?? linked?.walletName;
    if (profile == null || linked == null || name == null) return;

    final address = await _connect(name, silent: false);
    if (address == linked.address && linked.walletName != name) {
      final remembered =
          LinkedArNSWallet(address: linked.address, walletName: name);
      await _store.link(profile, remembered);
      if (!isClosed) emit(state.copyWith(linked: () => remembered));
    }
  }

  /// Forgets this profile's ArNS wallet and disconnects it.
  Future<void> unlink() async {
    final profile = state.profileAddress;
    if (profile == null) return;

    await _store.unlink(profile);
    try {
      await _arioSDK.disconnectSolanaWallet();
    } catch (e) {
      logger.w('Could not disconnect the Solana wallet: $e');
    }
    if (!isClosed) {
      emit(state.copyWith(
        linked: () => null,
        connectedAddress: () => null,
        connectedWalletName: () => null,
      ));
    }
  }

  /// What signs the owner proof and transactions, while connected on the
  /// linked account.
  ArNSOwnerSigner? get ownerSigner {
    final linked = state.linked;
    if (state.status != ArNSWalletStatus.connected || linked == null) {
      return null;
    }
    return BridgeArNSOwnerSigner(arioSDK: _arioSDK, address: linked.address);
  }

  Future<String?> _connect(String walletName, {required bool silent}) async {
    emit(state.copyWith(connecting: true));
    try {
      final address =
          await _arioSDK.connectSolanaWallet(walletName, silent: silent);
      if (isClosed) return address;
      emit(state.copyWith(
        connecting: false,
        connectedAddress: () => address,
        connectedWalletName: () => address == null ? null : walletName,
      ));
      return address;
    } catch (e) {
      // A rejected prompt or a wallet that went away: not connected.
      logger.w('Could not connect the Solana wallet: $e');
      if (!isClosed) emit(state.copyWith(connecting: false));
      if (!silent) rethrow;
      return null;
    }
  }

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    return super.close();
  }
}
