import 'dart:typed_data';

import 'package:ardrive/arns/data/turbo_arns_action_client.dart';
import 'package:ario_sdk/ario_sdk.dart';

/// The connected wallet switched to another account than the one asked to
/// sign.
class ArNSWrongAccountException implements Exception {
  const ArNSWrongAccountException({
    required this.expected,
    required this.connected,
  });

  final String expected;
  final String? connected;

  @override
  String toString() =>
      'ArNSWrongAccountException: expected $expected, connected $connected';
}

/// The linked ArNS wallet, signing through the Wallet Standard bridge.
/// Refuses to sign when the wallet is on another account, so a proof never
/// carries a key Turbo will reject.
class BridgeArNSOwnerSigner implements ArNSOwnerSigner {
  BridgeArNSOwnerSigner({required ArioSDK arioSDK, required this.address})
      : _arioSDK = arioSDK;

  final ArioSDK _arioSDK;

  @override
  final String address;

  void _checkAccount() {
    final connected = _arioSDK.connectedSolanaAddress;
    if (connected != address) {
      throw ArNSWrongAccountException(expected: address, connected: connected);
    }
  }

  @override
  Future<Uint8List> signMessage(Uint8List message) {
    _checkAccount();
    return _arioSDK.solanaSignMessage(message);
  }

  @override
  Future<String> signTransaction(String transactionBase64) {
    _checkAccount();
    return _arioSDK.solanaSignTransaction(transactionBase64);
  }
}
