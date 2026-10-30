import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/services/ethereum/ethereum_wallet.dart';
import 'package:bip39/bip39.dart' as bip39;
// ignore: depend_on_referenced_packages
import 'package:convert/convert.dart';

/// The message an Ethereum wallet signs to sign in to ArDrive, the first
/// thing asked of it. Its signature, hashed, is the private key of the
/// account's "auth" Ethereum key, which an account made before ArDrive 3.0
/// posted a verification record from at sign-up. Fixed forever: see
/// docs/ArweaveFS.md, "Browser wallet identities".
const ethereumVerifyMessage = 'Sign message to verify wallet address.';

/// The message a new MetaMask account (ArDrive 3.0 on) signs for its Arweave
/// wallet: readable, versioned, and with no password, nonce or date in it, so
/// the same Ethereum account always gets the same Arweave wallet.
///
/// Fixed forever: changing one byte gives every such account another
/// wallet. A new scheme gets a new version and a new function.
///
/// Signing it gives whoever asked for it the account, as the Solana identity
/// message does, so it says so.
String ethereumAccountMessage(String address) => 'ArDrive account\n'
    'Signing this opens your ArDrive account. Only sign it in ArDrive.\n'
    'It is free and sends no transaction.\n'
    'Account: ${address.toLowerCase()}\n'
    'Version: 2';

/// The recovery phrase of a new MetaMask account's Arweave wallet, from its
/// signature of [ethereumAccountMessage]: the first 16 bytes of the
/// signature's SHA-256 as BIP-39 entropy, as the Solana and the password
/// derivations do.
///
/// An Ethereum account's `personal_sign` is deterministic (RFC 6979), so the
/// same account always gets the same phrase. Smart-contract and MPC wallets
/// aren't, and never were under the password scheme either.
Future<String> deriveMnemonicFromEthereumAccountSignature(
  Uint8List signature,
) async {
  if (signature.length != 65) {
    throw ArgumentError(
      'Expected a 65-byte Ethereum signature, got ${signature.length} bytes',
    );
  }
  final digest = await sha256.hash(signature);
  return bip39.entropyToMnemonic(hex.encode(digest.bytes.sublist(0, 16)));
}

/// Asks [wallet] to sign [ethereumAccountMessage] and returns the new
/// account's recovery phrase.
Future<String> deriveEthereumAccountMnemonic(EthereumWallet wallet) async {
  final message = ethereumAccountMessage(await wallet.getAddress());
  final signature =
      await wallet.sign(Uint8List.fromList(utf8.encode(message)));
  return deriveMnemonicFromEthereumAccountSignature(signature);
}
