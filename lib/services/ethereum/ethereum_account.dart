import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/services/ethereum/ethereum_wallet.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:collection/collection.dart' show IterableExtension, mergeSort;
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
  const AccountRecordTx({required this.id, this.tags = const {}, this.height});

  final String id;
  final Map<String, String> tags;

  /// Its block, or null while it is pending.
  final int? height;
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
  const EthereumV2Marker(
    super.txId, {
    this.accountAddress,
    this.laterV1RecordId,
    this.records = const [],
  });

  final String? accountAddress;

  /// An untagged record that came after the marker: an old build, after a
  /// rollback, made a password account on this auth key too. If the wallet
  /// the account message derives isn't the marker's, the password is the
  /// way in, checked against this record.
  final String? laterV1RecordId;

  /// The records this was classified from, earliest first. The marker is
  /// only a candidate until the wallet the account message derives is
  /// known: [classifyAccountRecords] again with that address confirms it.
  final List<AccountRecordTx> records;
}

bool _isMarker(AccountRecordTx tx) => tx.tags[ethereumAccountVersionTag] == '2';

bool _isV1Record(AccountRecordTx tx) =>
    !tx.tags.containsKey(ethereumAccountVersionTag);

/// Which account an auth key's transactions [txs], earliest first, are for:
/// the earliest record decides.
///
/// - A real version 1 record (2024 to 2026) always predates any marker, so
///   a marker posted later by someone who phished the verify signature
///   can't take a version 1 account over.
/// - A version 1 record an old build posts after a rollback always comes
///   after the real marker, so it can't take a version 2 account over.
///
/// The verify message is the same for everyone, so anyone holding its
/// signature can post records under the auth key. A marker counts only if
/// its `ArDrive-Account-Address` is [accountAddress], the address the
/// account message's signature derives: a forged one can lock an account
/// out at worst, never open it. Markers that don't match are skipped (and
/// logged), so the earliest *matching* marker beats a later version 1
/// record, and a version 1 record earlier than any matching marker still
/// means version 1.
///
/// While [accountAddress] is null (before the account message is signed)
/// every marker is a candidate, and the result is an [EthereumV2Marker]
/// carrying [EthereumV2Marker.records] to be classified again once the
/// address is known.
///
/// Null when there are none.
EthereumAccountRecord? classifyAccountRecords(
  List<AccountRecordTx> txs, {
  String? accountAddress,
}) {
  for (var i = 0; i < txs.length; i++) {
    final tx = txs[i];
    if (_isMarker(tx)) {
      final address = tx.tags[ethereumAccountAddressTag];
      if (accountAddress != null && address != accountAddress) {
        logger.w('Ignoring an account marker for another address: ${tx.id}');
        continue;
      }
      return EthereumV2Marker(
        tx.id,
        accountAddress: address,
        laterV1RecordId: txs.skip(i + 1).where(_isV1Record).firstOrNull?.id,
        records: txs,
      );
    }
    if (_isV1Record(tx)) return EthereumV1Record(tx.id);
  }
  return null;
}

/// The [answers] of several endpoints as one list, earliest first, each
/// transaction once: by block, with pending transactions (no block yet)
/// after every mined one, whatever order an endpoint listed them in. Equal
/// heights keep the order of the endpoint asked last (the turbo-gateway
/// index), then of those before it.
List<AccountRecordTx> mergeAccountRecords(
  List<List<AccountRecordTx>> answers,
) {
  final byId = <String, AccountRecordTx>{};
  for (final answer in answers.reversed) {
    for (final tx in answer) {
      final known = byId[tx.id];
      if (known == null) {
        byId[tx.id] = tx;
      } else if (known.height == null && tx.height != null) {
        // Mined since the other endpoint saw it.
        byId[tx.id] = tx;
      }
    }
  }
  final merged = byId.values.toList();
  mergeSort(merged, compare: (a, b) {
    final ha = a.height, hb = b.height;
    if (ha == null && hb == null) return 0;
    if (ha == null) return 1;
    if (hb == null) return -1;
    return ha.compareTo(hb);
  });
  return merged;
}

/// An auth key's account record, looked for on each of [endpoints] in turn:
/// the configured GraphQL endpoint, then the turbo-gateway index (see
/// [firstReachable]). The earliest record across the endpoints asked
/// decides ([classifyAccountRecords]).
///
/// - A record found (a marker or a version 1 record) still asks the
///   endpoints after it, for an earlier record the first doesn't index (an
///   old build may have posted version 1 records under a version 2
///   account's auth key, or a forged marker may sit on one gateway). If
///   that extra check fails, the record found stands.
/// - "No record" is only the answer once every endpoint has answered and
///   none has one: an index can lag or miss items, and a wrong "no record"
///   would make an existing account a new, empty one. Any endpoint failing
///   (a 429 or 5xx included) throws, so a failed lookup is never read as "no
///   record". The question "Have you used ArDrive with this MetaMask
///   before?" is the safety net for an index that answers but misses the
///   record.
Future<EthereumAccountRecord?> findAccountRecordAcross(
  List<Future<List<AccountRecordTx>> Function()> endpoints,
) async {
  final answers = <List<AccountRecordTx>>[];
  EthereumAccountRecord? decide() =>
      classifyAccountRecords(mergeAccountRecords(answers));

  for (final lookup in endpoints) {
    final soFar = decide();
    if (soFar == null) {
      // Nothing yet: an endpoint that fails is a failure.
      answers.add(await lookup());
      continue;
    }
    // A record is known (a marker or a version 1 record): the next
    // endpoint is still asked, for an earlier one it alone has. If it
    // fails, what is known stands.
    try {
      answers.add(await lookup());
    } catch (e) {
      return soFar;
    }
  }
  return decide();
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
