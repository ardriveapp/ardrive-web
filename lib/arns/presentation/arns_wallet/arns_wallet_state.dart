part of 'arns_wallet_cubit.dart';

/// Where the ArNS wallet stands, for the button that asks for it at commit
/// and the profile card row (docs/NAMES.md, "Wallets and paying").
enum ArNSWalletStatus {
  /// Names are off, or nobody is signed in.
  unavailable,

  /// No ArNS wallet linked to this profile: "Link a Solana wallet".
  notLinked,

  /// Linked and remembered, but not connected now: names are readable,
  /// changes need "Reconnect Solana wallet".
  disconnected,

  /// Connected on the linked account: ready to approve.
  connected,

  /// Connected on another account: "Switch to … in your wallet, or change
  /// your ArNS wallet."
  wrongAccount,
}

class ArNSWalletState extends Equatable {
  const ArNSWalletState({
    this.enabled = false,
    this.profileAddress,
    this.linked,
    this.connectedAddress,
    this.connectedWalletName,
    this.installedWallets = const [],
    this.connecting = false,
  });

  final bool enabled;

  /// The signed-in ArDrive wallet, which the link belongs to.
  final String? profileAddress;
  final LinkedArNSWallet? linked;
  final String? connectedAddress;
  final String? connectedWalletName;

  /// Solana wallets on this device. Empty is common on phones: "No Solana
  /// wallet found".
  final List<SolanaWalletInfo> installedWallets;
  final bool connecting;

  bool get noWalletInstalled => installedWallets.isEmpty;

  ArNSWalletStatus get status {
    if (!enabled || profileAddress == null) {
      return ArNSWalletStatus.unavailable;
    }
    final linked = this.linked;
    if (linked == null) return ArNSWalletStatus.notLinked;
    if (connectedAddress == null) return ArNSWalletStatus.disconnected;
    return connectedAddress == linked.address
        ? ArNSWalletStatus.connected
        : ArNSWalletStatus.wrongAccount;
  }

  ArNSWalletState copyWith({
    bool? enabled,
    String? Function()? profileAddress,
    LinkedArNSWallet? Function()? linked,
    String? Function()? connectedAddress,
    String? Function()? connectedWalletName,
    List<SolanaWalletInfo>? installedWallets,
    bool? connecting,
  }) {
    return ArNSWalletState(
      enabled: enabled ?? this.enabled,
      profileAddress:
          profileAddress != null ? profileAddress() : this.profileAddress,
      linked: linked != null ? linked() : this.linked,
      connectedAddress:
          connectedAddress != null ? connectedAddress() : this.connectedAddress,
      connectedWalletName: connectedWalletName != null
          ? connectedWalletName()
          : this.connectedWalletName,
      installedWallets: installedWallets ?? this.installedWallets,
      connecting: connecting ?? this.connecting,
    );
  }

  @override
  List<Object?> get props => [
        enabled,
        profileAddress,
        linked,
        connectedAddress,
        connectedWalletName,
        installedWallets,
        connecting,
      ];
}
