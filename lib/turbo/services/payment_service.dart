import 'dart:convert';

import 'package:ardrive/turbo/topup/models/payment_model.dart';
import 'package:ardrive/turbo/utils/get_signature_headers_for_turbo.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/turbo_utils.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_logger/ardrive_logger.dart';
import 'package:arweave/arweave.dart';
import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class TurboBalanceInterface {
  final BigInt balance;
  final List<String> paidBy;

  TurboBalanceInterface({
    required this.balance,
    required this.paidBy,
  });

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

  Future<PriceForFiat> getPriceForFiat({
    required Wallet? wallet,
    required double amount,
    required String currency,
    String? promoCode,
  }) async {
    final Map<String, dynamic> signatureHeaders =
        await turboSignatureHeadersManager.getSignatureHeaders(
      wallet: wallet,
    );
    final result = await _requestPriceForFiat(
      httpClient,
      signatureHeaders: signatureHeaders,
      amount: amount,
      currency: currency,
      turboPaymentUri: turboPaymentUri,
      promoCode: promoCode,
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
      final receivedApprovals = data['receivedApprovals'] as List<dynamic>;
      if (receivedApprovals.isEmpty) {
        logger.w('No received approvals found for the user');
      }
      final paidBy = receivedApprovals
          .map((approval) => approval['payingAddress'] as String)
          .toList();

      return TurboBalanceInterface(
        balance: balance,
        paidBy: paidBy,
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

  Future<BigInt> getBalance({
    required Wallet wallet,
  }) async {
    final turboBalance = await getBalanceAndPaidBy(wallet: wallet);
    return turboBalance.balance;
  }

  Future<PaymentModel> getPaymentIntent({
    required Wallet wallet,
    required double amount,
    String currency = 'usd',
    String? promoCode,
  }) async {
    final nonce = const Uuid().v4();
    final walletAddress = await wallet.getAddress();
    final publicKey = await wallet.getOwner();
    final signature = await signNonceAndData(
      nonce: nonce,
      wallet: wallet,
    );

    final urlParams = promoCode != null && promoCode.isNotEmpty
        ? '?promoCode=$promoCode'
        : '';

    final result = await httpClient.get(
      url:
          '$turboPaymentUri/v1/top-up/payment-intent/$walletAddress/$currency/$amount$urlParams',
      headers: {
        'x-nonce': nonce,
        'x-signature': signature,
        'x-public-key': publicKey,
      },
    );

    return PaymentModel.fromJson(jsonDecode(result.data));
  }

  Future<List<String>> getSupportedCountries() async {
    final result = await httpClient.get(
      url: '$turboPaymentUri/v1/countries',
    );

    return List<String>.from(jsonDecode(result.data));
  }

  Future<int> redeemGift({
    required String email,
    required String giftCode,
    required String destinationAddress,
  }) async {
    try {
      final result = await httpClient.get(
        url:
            '$turboPaymentUri/v1/redeem?id=$giftCode&email=$email&destinationAddress=$destinationAddress',
        responseType: ResponseType.json,
      );

      logger.d('Gift redeem result: ${result.data}');

      if (result.statusCode != 200) {
        throw Exception(
            'Gift redeem failed with status code ${result.statusCode}');
      }

      final newBalance = result.data['userBalance'] as String;

      return int.parse(newBalance);
    } on ArDriveHTTPException catch (e) {
      if (e.data == 'Gift has already been redeemed!') {
        logger.e('Gift has already been redeemed!');
        throw GiftAlreadyRedeemed();
      }
      rethrow;
    } catch (e) {
      logger.d(e.toString());
      rethrow;
    }
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
  required Map<String, dynamic> signatureHeaders,
  required double amount,
  required String currency,
  required Uri turboPaymentUri,
  required String? promoCode,
}) async {
  final acceptedStatusCodes = [200, 202, 204];
  final String urlParams = _urlParamsForGetPriceForFiat(promoCode: promoCode);

  try {
    final result = await httpClient.get(
      url: '$turboPaymentUri/v1/price/$currency/$amount$urlParams',
      headers: signatureHeaders,
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
        logger.e('Invalid promo code: $promoCode');
        throw PaymentServiceInvalidPromoCode(promoCode: promoCode);
      }
    }

    throw PaymentServiceException(
      'Turbo price fetch failed with exception: $error',
    );
  }
}

String _urlParamsForGetPriceForFiat({
  required String? promoCode,
}) {
  final urlParams =
      promoCode != null && promoCode.isNotEmpty ? '?promoCode=$promoCode' : '';

  return urlParams;
}

class TurboUserNotFound implements UntrackedException {
  TurboUserNotFound();
}

class GiftAlreadyRedeemed implements Exception {
  GiftAlreadyRedeemed();
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
