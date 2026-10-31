import 'dart:convert';

import 'package:ardrive/turbo/models/turbo_free_allowance.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/payment_model.dart';
import 'package:ardrive/turbo/utils/get_signature_headers_for_turbo.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_logger/ardrive_logger.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';

/// A wallet's top-ups as `GET /v1/account/payments` returned them.
class TurboPaymentHistory {
  const TurboPaymentHistory({required this.payments, required this.complete});

  final List<Map<String, dynamic>> payments;

  /// False when there were more pages than were read.
  final bool complete;
}

/// One page of `GET /v1/account/payments`, rows as the service sent them.
class TurboPaymentsPage {
  const TurboPaymentsPage({
    required this.payments,
    required this.hasMore,
    required this.cursor,
  });

  final List<Map<String, dynamic>> payments;
  final bool hasMore;

  /// Where the next page starts; null on the last.
  final String? cursor;
}

/// Credits one wallet lets another spend (an entry of `givenApprovals` or
/// `receivedApprovals`).
class TurboCreditApproval {
  const TurboCreditApproval({
    required this.approvedAddress,
    required this.payingAddress,
    required this.approvedWinc,
    required this.usedWinc,
    this.expiresAt,
  });

  factory TurboCreditApproval.fromJson(Map<String, dynamic> json) =>
      TurboCreditApproval(
        approvedAddress: '${json['approvedAddress'] ?? ''}',
        payingAddress: '${json['payingAddress'] ?? ''}',
        approvedWinc:
            BigInt.tryParse('${json['approvedWincAmount']}') ?? BigInt.zero,
        usedWinc: BigInt.tryParse('${json['usedWincAmount']}') ?? BigInt.zero,
        expiresAt: DateTime.tryParse('${json['expirationDate'] ?? ''}'),
      );

  /// Who may spend the credits.
  final String approvedAddress;

  /// Whose credits they are.
  final String payingAddress;
  final BigInt approvedWinc;
  final BigInt usedWinc;
  final DateTime? expiresAt;

  BigInt get leftWinc {
    final left = approvedWinc - usedWinc;
    return left < BigInt.zero ? BigInt.zero : left;
  }
}

/// A wallet's Turbo balance with the credits shared to and from it.
class TurboBalanceDetails {
  const TurboBalanceDetails({
    required this.effective,
    required this.controlled,
    required this.given,
    required this.received,
  });

  /// What the wallet can spend: its own plus what is left of shared credits.
  final BigInt effective;

  /// Its own credits.
  final BigInt controlled;
  final List<TurboCreditApproval> given;
  final List<TurboCreditApproval> received;
}

/// The signature for a signed Turbo read could not be made: a wallet that
/// asked to approve and was refused, or could not sign.
class TurboSignatureException implements Exception {
  TurboSignatureException(this.message);

  final String message;

  @override
  String toString() => 'Exception: $message';
}

class TurboBalanceInterface {
  /// What the wallet can spend now: its own credits plus what is left of
  /// credits other wallets have shared with it (Turbo's `effectiveBalance`).
  final BigInt balance;
  final List<String> paidBy;

  /// The wallet's own credits alone, including any it has shared that have
  /// not been spent yet (Turbo's `controlledWinc`). Credits shared *to* it
  /// are not in here. Where only [balance] is known, it is that.
  BigInt get controlledWinc => _controlledWinc ?? balance;
  final BigInt? _controlledWinc;

  TurboBalanceInterface({
    required this.balance,
    required this.paidBy,
    BigInt? controlledWinc,
  }) : _controlledWinc = controlledWinc;

  @override
  String toString() {
    return 'TurboBalanceInterface{balance: $balance, paidBy: $paidBy}';
  }
}

class PaymentService {
  final bool useTurboPayment = true;
  final Uri turboPaymentUri;
  final TurboSignatureHeadersManager turboSignatureHeadersManager;

  ArDriveHTTP httpClient;

  PaymentService({
    required this.turboPaymentUri,
    required this.httpClient,
    required this.turboSignatureHeadersManager,
  });

  Future<BigInt> getPriceForBytes({
    required int byteSize,
  }) async {
    final acceptedStatusCodes = [200, 202, 204];
    final result = await httpClient.get(
      url: '$turboPaymentUri/v1/price/bytes/$byteSize',
    );
    if (!acceptedStatusCodes.contains(result.statusCode)) {
      throw Exception(
        'Turbo price fetch failed with status code ${result.statusCode}',
      );
    }
    final price = BigInt.parse((json.decode(result.data)['winc']));

    return price;
  }

  /// What 1 GiB costs in US dollars, Turbo's fees included: `fiat.usd` from
  /// `GET /v1/rates`. The rate the price calculator shows as "1 GB".
  Future<double> getUsdPerGiB() async {
    final result = await httpClient.get(url: '$turboPaymentUri/v1/rates');
    if (result.statusCode != 200) {
      throw Exception(
        'Turbo rates fetch failed with status code ${result.statusCode}',
      );
    }
    final fiat = json.decode(result.data)['fiat'] as Map<String, dynamic>;
    return (fiat['usd'] as num).toDouble();
  }

  Future<PriceForFiat> getPriceForFiat({
    required Wallet? wallet,
    required double amount,
    required String currency,
    String? promoCode,
  }) async {
    final walletAddress = await wallet?.getAddress();

    final result = await _requestPriceForFiat(
      httpClient,
      amount: amount,
      currency: currency,
      turboPaymentUri: turboPaymentUri,
      promoCode: promoCode,
      walletAddress: walletAddress,
    );

    return _parseHttpResponseForPriceForFiat(result);
  }

  Future<TurboBalanceInterface> getBalanceAndPaidBy({
    required Wallet wallet,
  }) async {
    try {
      final result = await httpClient.get(
        url:
            '$turboPaymentUri/v1/account/balance/arweave?address=${await wallet.getAddress()}',
      );

      final data = json.decode(result.data);
      final balance = BigInt.parse(data['effectiveBalance']);
      final controlled = BigInt.tryParse('${data['controlledWinc']}');
      final receivedApprovals = data['receivedApprovals'] as List<dynamic>;
      final paidBy = receivedApprovals
          .map((approval) => approval['payingAddress'] as String)
          .toList();

      return TurboBalanceInterface(
        balance: balance,
        paidBy: paidBy,
        controlledWinc: controlled,
      );
    } catch (error, stackTrace) {
      if (error is ArDriveHTTPException) {
        if (error.statusCode == 404) {
          logger.w('user not found');
          throw TurboUserNotFound();
        }
      }
      logger.e('error getting balance', error, stackTrace);
      rethrow;
    }
  }

  /// The wallet's own completed top-ups, card and crypto, newest first.
  ///
  /// A signed request: the service reads whose history it is from the
  /// signature, so it can only ever return the signer's own. The signature
  /// headers are cached per wallet, so a wallet that has already signed for
  /// Turbo this session is not asked again.
  ///
  /// Reads up to [maxPages] pages of a hundred rows, and says whether that
  /// was all of it: a history cut short is not a smaller history, and must
  /// not be read as one.
  Future<TurboPaymentHistory> getPaymentHistory({
    required Wallet wallet,
    int maxPages = 10,
  }) async {
    final payments = <Map<String, dynamic>>[];
    String? cursor;
    var complete = false;

    for (var page = 0; page < maxPages; page++) {
      final query = cursor == null
          ? 'limit=100'
          : 'limit=100&cursor=${Uri.encodeQueryComponent(cursor)}';
      final result = await _signedGet(
        wallet,
        '$turboPaymentUri/v1/account/payments?$query',
      );
      final data = json.decode(result.data) as Map<String, dynamic>;

      payments.addAll(
        (data['payments'] as List<dynamic>).cast<Map<String, dynamic>>(),
      );

      cursor = data['cursor'] as String?;

      if (data['hasMore'] != true || cursor == null) {
        complete = true;
        break;
      }
    }

    return TurboPaymentHistory(payments: payments, complete: complete);
  }

  /// A signed read. Turbo refusing the cached headers (401 or 403) drops them
  /// and tries once more with fresh ones; any other failure is the caller's.
  Future<ArDriveHTTPResponse> _signedGet(Wallet wallet, String url) async {
    final headers = await turboSignatureHeadersManager.getSignatureHeaders(
      wallet: wallet,
    );
    try {
      return await httpClient.get(url: url, headers: headers);
    } on ArDriveHTTPException catch (e) {
      if (e.statusCode != 401 && e.statusCode != 403) rethrow;
      turboSignatureHeadersManager.clearCache();
      final fresh = await turboSignatureHeadersManager.getSignatureHeaders(
        wallet: wallet,
      );
      return httpClient.get(url: url, headers: fresh);
    }
  }

  /// One page of the wallet's own top-ups, newest first. Signed like
  /// [getPaymentHistory]; the cached signature headers are reused for every
  /// page (checked against production: Turbo accepts a reused nonce).
  Future<TurboPaymentsPage> getPaymentHistoryPage({
    required Wallet wallet,
    String? cursor,
    int limit = 50,
  }) async {
    final query = cursor == null
        ? 'limit=$limit'
        : 'limit=$limit&cursor=${Uri.encodeQueryComponent(cursor)}';
    final result = await _signedGet(
      wallet,
      '$turboPaymentUri/v1/account/payments?$query',
    );
    final data = json.decode(result.data) as Map<String, dynamic>;
    final next = data['cursor'] as String?;

    return TurboPaymentsPage(
      payments: ((data['payments'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(),
      hasMore: data['hasMore'] == true && next != null,
      cursor: next,
    );
  }

  /// The wallet's balance with the credits it has shared and was shared.
  /// Throws [TurboUserNotFound] for an account Turbo has never seen.
  Future<TurboBalanceDetails> getBalanceDetails({
    required Wallet wallet,
  }) async {
    try {
      final result = await httpClient.get(
        url:
            '$turboPaymentUri/v1/account/balance/arweave?address=${await wallet.getAddress()}',
      );
      final data = json.decode(result.data) as Map<String, dynamic>;
      List<TurboCreditApproval> approvals(String key) =>
          ((data[key] as List<dynamic>?) ?? const [])
              .whereType<Map>()
              .map((a) =>
                  TurboCreditApproval.fromJson(Map<String, dynamic>.from(a)))
              .toList();
      final effective = BigInt.parse('${data['effectiveBalance']}');

      return TurboBalanceDetails(
        effective: effective,
        controlled: BigInt.tryParse('${data['controlledWinc']}') ?? effective,
        given: approvals('givenApprovals'),
        received: approvals('receivedApprovals'),
      );
    } catch (error) {
      if (error is ArDriveHTTPException && error.statusCode == 404) {
        throw TurboUserNotFound();
      }
      rethrow;
    }
  }

  Future<BigInt> getBalance({
    required Wallet wallet,
  }) async {
    final turboBalance = await getBalanceAndPaidBy(wallet: wallet);
    return turboBalance.balance;
  }

  /// What an address holds in one of Turbo's chain-scoped accounts.
  ///
  /// Separate from [getBalanceAndPaidBy] because the inputs and the purpose are
  /// different. That one takes a [Wallet], derives its address and asks about
  /// money this app is going to spend. This takes a bare address on a chain the
  /// app holds no wallet for, and asks a diagnostic question: is the balance
  /// somebody is looking for sitting somewhere we never look?
  ///
  /// Nothing returned here is spendable. Turbo bills the account that signs the
  /// upload, so credits on a sign-in wallet stay where they are until their
  /// owner shares them across.
  ///
  /// Returns zero for an account Turbo has never seen, because 404 is how Turbo
  /// says "no such account" and for this question that is the same answer as
  /// "nothing there".
  Future<BigInt> getBalanceForAddress({
    required String address,
    required WalletType walletType,
  }) async {
    try {
      final result = await httpClient.get(
        url: '$turboPaymentUri/v1/account/balance/'
            '${walletType.turboTokenNamespace}?address=$address',
      );

      return BigInt.parse(json.decode(result.data)['effectiveBalance']);
    } catch (error) {
      if (error is ArDriveHTTPException && error.statusCode == 404) {
        return BigInt.zero;
      }

      rethrow;
    }
  }

  /// Fetches how much of the wallet's Turbo free-upload allowance is left.
  ///
  /// Advisory only — see [TurboFreeAllowance]. Throws on transport/HTTP
  /// failure; callers are expected to fall back to
  /// [TurboFreeAllowance.unknown] rather than block the upload.
  Future<TurboFreeAllowance> getFreeAllowance({
    required Wallet wallet,
  }) async {
    final result = await httpClient.get(
      url:
          '$turboPaymentUri/v1/account/free?address=${await wallet.getAddress()}',
    );

    final raw = result.data;

    return TurboFreeAllowance.fromJson(raw is String ? json.decode(raw) : raw);
  }

  Future<PaymentModel> getPaymentIntent({
    required Wallet wallet,
    required double amount,
    String currency = 'usd',
    String? promoCode,
  }) async {
    final walletAddress = await wallet.getAddress();

    final urlParams = _urlParamsForGetPriceForFiat(promoCode: promoCode);

    // Ensure amount is formatted as integer (no decimal point) for the API
    final amountInt = amount.toInt();
    final result = await httpClient.get(
      url:
          '$turboPaymentUri/v1/top-up/payment-intent/$walletAddress/$currency/$amountInt$urlParams',
    );

    return PaymentModel.fromJson(jsonDecode(result.data));
  }

  Future<List<String>> getSupportedCountries() async {
    final result = await httpClient.get(
      url: '$turboPaymentUri/v1/countries',
    );

    return List<String>.from(jsonDecode(result.data));
  }
}

PriceForFiat _parseHttpResponseForPriceForFiat(
  ArDriveHTTPResponse response,
) {
  final parsedData = json.decode(response.data);

  final winc = BigInt.parse(parsedData['winc']);
  final int? actualPaymentAmount = parsedData['actualPaymentAmount'];
  final int? quotedPaymentAmount = parsedData['quotedPaymentAmount'];
  final adjustments = ((parsedData['adjustments'] ?? const []) as List)
      .map((e) => Adjustment.fromJson(e))
      .toList();

  return PriceForFiat(
    winc: winc,
    actualPaymentAmount: actualPaymentAmount,
    quotedPaymentAmount: quotedPaymentAmount,
    adjustments: adjustments,
  );
}

Future<ArDriveHTTPResponse> _requestPriceForFiat(
  ArDriveHTTP httpClient, {
  required double amount,
  required String currency,
  required Uri turboPaymentUri,
  required String? walletAddress,
  required String? promoCode,
}) async {
  final acceptedStatusCodes = [200, 202, 204];
  final String urlParams = _urlParamsForGetPriceForFiat(
      promoCode: promoCode, walletAddress: walletAddress);

  // Convert amount to integer to avoid decimal in URL (e.g., 1000.0 -> 1000)
  // The API expects amount in cents as an integer
  final int amountCents = amount.round();

  try {
    final result = await httpClient.get(
      url: '$turboPaymentUri/v1/price/$currency/$amountCents$urlParams',
    );

    if (!acceptedStatusCodes.contains(result.statusCode)) {
      throw PaymentServiceException(
        'Turbo price fetch failed with status code ${result.statusCode}',
      );
    }

    return result;
  } catch (error) {
    if (error is ArDriveHTTPException) {
      if (error.statusCode == 400) {
        // Check the actual error response to provide a more specific error message
        final errorData = error.data;
        final errorMessage = errorData?.toString() ?? '';

        // Check if it's actually a promo code error
        if (promoCode != null &&
            promoCode.isNotEmpty &&
            (errorMessage.toLowerCase().contains('promo') ||
                errorMessage.toLowerCase().contains('coupon') ||
                errorMessage.toLowerCase().contains('code'))) {
          logger.e('Invalid promo code: $promoCode - $errorMessage');
          throw PaymentServiceInvalidPromoCode(promoCode: promoCode);
        }

        // Log the actual error and throw a general exception
        logger.e('API returned 400: $errorMessage');
        throw PaymentServiceException(
          'Price fetch failed: ${errorMessage.isNotEmpty ? errorMessage : 'Bad request'}',
        );
      }
    }

    throw PaymentServiceException(
      'Turbo price fetch failed with exception: $error',
    );
  }
}

String _urlParamsForGetPriceForFiat({
  required String? promoCode,
  String? walletAddress,
}) {
  final params = <String, String>{};

  if (promoCode != null && promoCode.isNotEmpty) {
    params['promoCode'] = promoCode;
  }

  if (walletAddress != null) {
    params['destinationAddress'] = walletAddress;
  }

  if (params.isEmpty) return '';

  return '?${params.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
}

class TurboUserNotFound implements UntrackedException {
  TurboUserNotFound();
}

class PaymentServiceException implements Exception, Equatable {
  final String message;

  PaymentServiceException([this.message = '']);

  @override
  String toString() {
    return 'PaymentServiceException{message: $message}';
  }

  @override
  List<Object> get props => [message];

  @override
  bool? get stringify => true;
}

class PaymentServiceInvalidPromoCode implements PaymentServiceException {
  final String? promoCode;

  const PaymentServiceInvalidPromoCode({required this.promoCode});

  @override
  String get message => 'Invalid promo code: "$promoCode"';

  @override
  String toString() {
    return 'PaymentServiceInvalidPromoCode{promoCode: $promoCode}';
  }

  @override
  List<Object> get props => [promoCode ?? ''];

  @override
  bool? get stringify => true;
}

class PriceForFiat extends Equatable {
  final BigInt winc;
  final int? actualPaymentAmount;
  final int? quotedPaymentAmount;
  final List<Adjustment> adjustments;

  bool get hasReachedMaximumDiscount {
    final maxDiscount = adjustments.first.maxDiscount;
    if (maxDiscount == null) {
      return false;
    }

    final adjustmentAmount = adjustments.first.adjustmentAmount;
    return maxDiscount + adjustmentAmount == 0;
  }

  String? get adjustmentAmount {
    if (adjustments.isEmpty) {
      return null;
    }

    final adjustmentAmount = -adjustments.first.adjustmentAmount / 100;
    return adjustmentAmount.toStringAsFixed(2);
  }

  String? get humanReadableDiscountPercentage {
    if (adjustments.isEmpty) {
      return null;
    }

    return adjustments.first.humanReadableDiscountPercentage;
  }

  BigInt get winstonCredits => winc;

  const PriceForFiat({
    required this.winc,
    required this.actualPaymentAmount,
    required this.quotedPaymentAmount,
    required this.adjustments,
  });

  factory PriceForFiat.zero() => PriceForFiat(
        winc: BigInt.zero,
        actualPaymentAmount: 0,
        quotedPaymentAmount: 0,
        adjustments: const [],
      );

  @override
  String toString() {
    return 'PriceForFiat{winc: $winc,'
        ' actualPaymentAmount: $actualPaymentAmount,'
        ' quotedPaymentAmount: $quotedPaymentAmount,'
        ' adjustments: $adjustments}';
  }

  @override
  List<Object> get props => [
        winc,
        actualPaymentAmount ?? '',
        quotedPaymentAmount ?? '',
        adjustments,
      ];
}
