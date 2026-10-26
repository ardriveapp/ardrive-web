import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/arns/domain/arns_action.dart';
import 'package:ardrive/arns/utils/base58.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arconnect/arconnect.dart';
import 'package:arweave/arweave.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// Turbo's sandbox payment service, which runs ArNS on Solana devnet.
const turboSandboxPaymentUrl = 'https://payment.services.ar-io.dev';

/// Signs the payer half of a Turbo signed request: the wallet whose credits
/// are debited.
abstract class ArNSPayerSigner {
  /// `x-nonce`, `x-signature` and `x-public-key` over [nonce].
  Future<Map<String, String>> signedRequestHeaders(String nonce);
}

/// The ArDrive wallet as payer. Every action gets its own nonce, so unlike
/// `TurboSignatureHeadersManager` nothing here is cached.
class ArweaveWalletPayer implements ArNSPayerSigner {
  ArweaveWalletPayer(this._wallet, {TabVisibilitySingleton? tabVisibility})
      : _tabVisibility = tabVisibility ?? TabVisibilitySingleton();

  final Wallet _wallet;
  final TabVisibilitySingleton _tabVisibility;

  @override
  Future<Map<String, String>> signedRequestHeaders(String nonce) async {
    final publicKey = await safeArConnectAction<String>(
      _tabVisibility,
      (_) => _wallet.getOwner(),
    );
    final signature = await safeArConnectAction<String>(
      _tabVisibility,
      (_) => signNonceAndData(nonce: nonce, wallet: _wallet),
    );

    return {
      'x-nonce': nonce,
      'x-signature': signature,
      'x-public-key': publicKey,
    };
  }
}

/// The ArNS wallet: the Solana key that owns the name. It approves; it never
/// pays.
abstract class ArNSOwnerSigner {
  /// The base58 Solana address, which is the 32-byte ed25519 public key.
  String get address;

  /// The 64-byte ed25519 signature over [message].
  Future<Uint8List> signMessage(Uint8List message);

  /// Signs a base64 transaction exactly as given and returns it, base64.
  Future<String> signTransaction(String transactionBase64);
}

/// Turbo's ArNS actions for record changes (docs/NAMES.md, "Writes"),
/// directly over HTTP so no key crosses into JavaScript but the ArNS
/// wallet's.
///
/// Credits are debited when an action is created, so nothing here ever
/// creates one twice: a failure after create is resolved through the nonce.
class TurboArNSActionClient {
  TurboArNSActionClient({
    required String Function() paymentUrl,
    http.Client? client,
    String Function()? newNonce,
    Future<void> Function(Duration)? delay,
  })  : _paymentUrl = paymentUrl,
        _client = client ?? http.Client(),
        _newNonce = newNonce ?? const Uuid().v4,
        _delay = delay ?? Future<void>.delayed;

  final String Function() _paymentUrl;
  final http.Client _client;
  final String Function() _newNonce;
  final Future<void> Function(Duration) _delay;

  /// How often a signed transaction is re-posted after "Blockhash not found".
  static const blockhashRetries = 3;
  static const _blockhashRetryDelay = Duration(seconds: 2);

  static const _ownerSignatureType = '4';

  Uri _uri(String path) {
    final base = _paymentUrl().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/v1/arns/actions/$path');
  }

  /// What creating [action] will debit, in winc.
  Future<BigInt> price(ArNSRecordAction action) async {
    final response = await _client.get(_uri('${action.path}/price'));
    if (response.statusCode != 200) {
      throw ArNSActionRequestException(
        _message(response),
        statusCode: response.statusCode,
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return BigInt.parse(json['wincQty'].toString());
  }

  /// The message the owner signs, before its nonce is appended. Turbo
  /// rebuilds it from the request, so it must match byte for byte.
  static String ownerProofMessage(ArNSRecordChange change) =>
      ['arns', change.action.path, ...change.proofFields].join('\n');

  static Future<Map<String, String>> ownerProofHeaders(
    ArNSOwnerSigner owner,
    String message,
    String proofNonce,
  ) async {
    final signature =
        await owner.signMessage(utf8.encode('$message$proofNonce'));

    return {
      'x-owner-public-key': _base64UrlNoPad(base58Decode(owner.address)),
      'x-owner-nonce': proofNonce,
      'x-owner-signature': _base64UrlNoPad(signature),
      'x-owner-signature-type': _ownerSignatureType,
    };
  }

  /// Creates the action, which debits the payer. Never call it twice for one
  /// change: resume with [status] and [sign] instead.
  Future<ArNSActionResult> create(
    ArNSRecordChange change, {
    required ArNSPayerSigner payer,
    required ArNSOwnerSigner owner,
  }) async {
    // The owner's prompt comes first: rejecting it must cost nothing, not
    // even a payer prompt.
    final proof = await ownerProofHeaders(
      owner,
      ownerProofMessage(change),
      _newNonce(),
    );
    final payerHeaders = await payer.signedRequestHeaders(_newNonce());

    final response = await _client.post(
      _uri(change.action.path),
      headers: {
        ...payerHeaders,
        ...proof,
        'content-type': 'application/json',
      },
      body: jsonEncode({...change.body, 'ownerAddress': owner.address}),
    );

    if (response.statusCode == 402) {
      throw ArNSInsufficientCreditsException(_message(response));
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ArNSActionRequestException(
        _message(response),
        statusCode: response.statusCode,
      );
    }
    return ArNSActionResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Submits the owner-signed transaction of an awaiting action. Safe to
  /// repeat with the same bytes. Sends no payer headers.
  Future<ArNSActionCompleted> sign(
      String nonce, String signedTransaction) async {
    final response = await _client.post(
      _uri('$nonce/sign'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'transaction': signedTransaction}),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final result = ArNSActionResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      if (result is ArNSActionCompleted) return result;
      throw ArNSActionRequestException(
        'Unexpected state after signing: $result',
        statusCode: response.statusCode,
      );
    }
    throw _signError(nonce, response);
  }

  /// An action's state, to resume after a lost response or a reload.
  Future<ArNSActionResult> status(String nonce) async {
    final response = await _client.get(_uri(nonce));
    if (response.statusCode != 200) {
      throw ArNSActionRequestException(
        _message(response),
        statusCode: response.statusCode,
      );
    }
    return ArNSActionResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Runs one change to completion: create, report the nonce through
  /// [onNonce] before any further prompt, and sign if Turbo asks.
  Future<ArNSActionCompleted> run(
    ArNSRecordChange change, {
    required ArNSPayerSigner payer,
    required ArNSOwnerSigner owner,
    required FutureOr<void> Function(ArNSActionResult created) onNonce,
  }) async {
    final created = await create(change, payer: payer, owner: owner);
    await onNonce(created);

    switch (created) {
      case ArNSActionCompleted():
        return created;
      case ArNSActionAwaitingSignature():
        final signed = await owner.signTransaction(created.transaction);
        return submitSigned(created.nonce, signed);
      case ArNSActionFailed():
        throw ArNSActionRequestException(
          'Action ${created.nonce} failed',
          statusCode: 200,
        );
      case ArNSActionInProgress():
        throw ArNSActionRequestException(
          'Action ${created.nonce} is ${created.status}',
          statusCode: 200,
        );
    }
  }

  /// [sign], re-posting the same bytes while Solana cannot find the
  /// blockhash.
  Future<ArNSActionCompleted> submitSigned(
    String nonce,
    String signedTransaction,
  ) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await sign(nonce, signedTransaction);
      } on ArNSBlockhashNotFoundException {
        if (attempt >= blockhashRetries) rethrow;
        await _delay(_blockhashRetryDelay);
      }
    }
  }

  ArNSActionException _signError(String nonce, http.Response response) {
    final status = response.statusCode;
    final message = _message(response);
    // Matched on the raw body, as turbo-sdk does.
    final body = response.body;
    bool says(String pattern) =>
        RegExp(pattern, caseSensitive: false).hasMatch(body);

    if (status == 402) return ArNSInsufficientCreditsException(message);
    if (status == 409 && says('expired')) {
      return ArNSActionExpiredException(
        message,
        nonce: nonce,
        refunded: _refunded(body) ?? says('credits have been returned'),
      );
    }
    // Matched on this nonce: the same status carries on-chain rejections
    // such as "Lease has expired" that are not about the action.
    if (status == 400 && body.contains('Action $nonce expired')) {
      return ArNSActionExpiredException(
        message,
        nonce: nonce,
        refunded: _refunded(body) ?? says('expired and was refunded'),
      );
    }
    if (status == 503 && says('blockhash not found')) {
      return ArNSBlockhashNotFoundException(message, nonce: nonce);
    }
    return ArNSActionRequestException(message, statusCode: status);
  }

  /// A `refunded` flag in a JSON body, when Turbo sends one.
  static bool? _refunded(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map && json['refunded'] is bool) {
        return json['refunded'] as bool;
      }
    } catch (_) {
      // Not JSON.
    }
    return null;
  }

  static String _message(http.Response response) {
    final body = response.body;
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        final text = json['error'] ?? json['message'];
        if (text is String) return text;
      }
    } catch (_) {
      // Not JSON: the body is the message.
    }
    return body.isEmpty ? 'HTTP ${response.statusCode}' : body;
  }

  static String _base64UrlNoPad(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}
