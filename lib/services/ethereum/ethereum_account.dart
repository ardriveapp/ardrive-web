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
  final signature = await wallet.sign(Uint8List.fromList(utf8.encode(message)));
  return deriveMnemonicFromEthereumAccountSignature(signature);
}

/// The tag that marks an auth key's record as a version 2 account's marker.
const ethereumAccountVersionTag = 'ArDrive-Account-Version';

/// The tag that carries the account's Arweave address on its marker, beside
/// the same address as the item's data.
const ethereumAccountAddressTag = 'ArDrive-Account-Address';

/// The tags of a version 2 account's marker: posted once, at sign-up, by
/// the account's auth key, so the next sign-in, on any device, knows the
/// account is version 2 and which Arweave address its wallet must derive.
/// The item's data is [arweaveAddress] as UTF-8.
Map<String, String> ethereumAccountMarkerTags(String arweaveAddress) => {
      'App-Name': 'ArDrive',
      ethereumAccountVersionTag: '2',
      ethereumAccountAddressTag: arweaveAddress,
    };

/// A transaction an auth key made, as an account lookup reads it.
class AccountRecordTx {
  const AccountRecordTx({required this.id, this.tags = const {}});

  final String id;
  final Map<String, String> tags;
}

/// What an auth key's records say about its account. See
/// [classifyAccountRecords].
sealed class EthereumAccountRecord {
  const EthereumAccountRecord(this.txId);

  final String txId;
}

/// A version 1 account (made before 3.0, with a password): an untagged
/// verification record.
class EthereumV1Record extends EthereumAccountRecord {
  const EthereumV1Record(super.txId);
}

/// A version 2 account (no password): its marker, and the Arweave address
/// its wallet derives, when the marker carries it as a tag.
class EthereumV2Marker extends EthereumAccountRecord {
  const EthereumV2Marker(super.txId, {this.accountAddress});

  final String? accountAddress;
}

/// Which account an auth key's transactions [txs] are for: a version 2
/// marker wins, then the first untagged record (version 1). Null when there
/// are none.
EthereumAccountRecord? classifyAccountRecords(List<AccountRecordTx> txs) {
  for (final tx in txs) {
    if (tx.tags[ethereumAccountVersionTag] == '2') {
      return EthereumV2Marker(tx.id,
          accountAddress: tx.tags[ethereumAccountAddressTag]);
    }
  }
  for (final tx in txs) {
    if (!tx.tags.containsKey(ethereumAccountVersionTag)) {
      return EthereumV1Record(tx.id);
    }
  }
  return null;
}

/// An auth key's account record, looked for on each of [endpoints] in turn:
/// the configured GraphQL endpoint, then the turbo-gateway index (see
/// [firstReachable]).
///
/// A record any endpoint has is the answer. "No record" is only the answer
/// once every endpoint has answered and none has one: an index can lag or
/// miss items, and a wrong "no record" would make an existing account a new,
/// empty one. Any endpoint failing (a 429 or 5xx included) throws, so a
/// failed lookup is never read as "no record". The question "Have you used
/// ArDrive with this MetaMask before?" is the safety net for an index that
/// answers but misses the record.
Future<EthereumAccountRecord?> findAccountRecordAcross(
  List<Future<List<AccountRecordTx>> Function()> endpoints,
) async {
  for (final lookup in endpoints) {
    final found = classifyAccountRecords(await lookup());
    if (found != null) return found;
  }
  return null;
}

/// The answer of the first of [domains] that answers: the same index
/// reached through another domain, for people blocked from one of them.
/// Throws [AccountLookupUnavailable] when none answers.
Future<T> firstReachable<T>(List<Future<T> Function()> domains) async {
  Object? last;
  for (final domain in domains) {
    try {
      return await domain();
    } catch (e) {
      last = e;
    }
  }
  throw AccountLookupUnavailable(last);
}

/// An index an account lookup needs couldn't be reached on any of its
/// domains. Never "no record".
class AccountLookupUnavailable implements Exception {
  const AccountLookupUnavailable(this.cause);

  final Object? cause;

  @override
  String toString() => 'AccountLookupUnavailable($cause)';
}
