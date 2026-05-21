import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:bip39/bip39.dart' as bip39;
// ignore: depend_on_referenced_packages
import 'package:convert/convert.dart';

/// Fixed message signed by Solana wallet to derive ArDrive identity.
/// MUST NEVER change — changing this invalidates all Solana-derived wallets.
/// This text is displayed to users in the Phantom/Solflare signing popup.
const solanaIdentityMessage =
    'ArDrive wants to access your account. '
    'Only approve this on a gateway you trust (e.g. app.ardrive.io). '
    'ArDrive Identity v1';

/// Derives a BIP39 mnemonic from a Solana wallet's Ed25519 signature.
///
/// The [signature] must be from signing [solanaIdentityMessage].
/// Ed25519 signatures are deterministic (RFC 8032), so the same wallet
/// always produces the same mnemonic → same Arweave identity.
Future<String> deriveMnemonicFromSolanaSignature(Uint8List signature) async {
  final signatureSha256 = await sha256.hash(signature);
  final halfSignature = signatureSha256.bytes.sublist(0, 16);
  return bip39.entropyToMnemonic(hex.encode(halfSignature));
}
