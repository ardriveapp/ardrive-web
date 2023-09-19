import 'dart:convert';

import 'package:ardrive/turbo/topup/models/payment_model.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/turbo_utils.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class PaymentService {
  final bool useTurboPayment = true;
  final Uri turboPaymentUri;

  ArDriveHTTP httpClient;

  PaymentService({
    required this.turboPaymentUri,
    required this.httpClient,
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
        _signatureHeadersForGetPriceForFiat(wallet: wallet);
    final result = await _requestPriceForFiat(
      httpClient,
      signatureHeaders: signatureHeaders,
      amount: amount,
      currency: currency,
      turboPaymentUri: turboPaymentUri,
    );

    return _parseHttpResponseForPriceForFiat(result);
  }

  Future<BigInt> getBalance({
    required Wallet wallet,
  }) async {
    final nonce = const Uuid().v4();
    final publicKey = await wallet.getOwner();
    final signature = await signNonceAndData(
      nonce: nonce,
      wallet: wallet,
    );
    final result = await httpClient.get(
      url: '$turboPaymentUri/v1/balance',
      headers: {
        'x-nonce': nonce,
        'x-signature': signature,
        'x-public-key': publicKey,
      },
    ).onError((ArDriveHTTPException error, stackTrace) {
      if (error.statusCode == 404) {
        logger.w('user not found');
        throw TurboUserNotFound();
      }

      logger.e('error getting balance', error, stackTrace);

      throw error;
    });

    final price = BigInt.parse((json.decode(result.data)['winc']));

    return price;
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
  required signatureHeaders,
  required double amount,
  required String currency,
  required Uri turboPaymentUri,
  String? promoCode,
}) async {
  final acceptedStatusCodes = [200, 202, 204];
  final String urlParams = _urlParamsForGetPriceForFiat(promoCode: promoCode);

  final result = await httpClient
      .get(
    url: '$turboPaymentUri/v1/price/$currency/$amount$urlParams',
    headers: signatureHeaders,
  )
      .onError(
    (ArDriveHTTPException error, stackTrace) {
      if (error.statusCode == 400) {
        logger.e('Invalid promo code: $promoCode');
        throw PaymentServiceInvalidPromoCode(promoCode: promoCode);
      }
      throw PaymentServiceException(
        'Turbo price fetch failed with status code ${error.statusCode}',
      );
    },
  );

  if (!acceptedStatusCodes.contains(result.statusCode)) {
    throw PaymentServiceException(
      'Turbo price fetch failed with status code ${result.statusCode}',
    );
  }

  return result;
}

Map<String, dynamic> _signatureHeadersForGetPriceForFiat({
  required Wallet? wallet,
}) {
  if (wallet == null) {
    return {};
  }

  final nonce = const Uuid().v4();
  final publicKey = wallet.getOwner();
  final signature = signNonceAndData(
    nonce: nonce,
    wallet: wallet,
  );

  return {
    'x-nonce': nonce,
    'x-signature': signature,
    'x-public-key': publicKey,
  };
}

String _urlParamsForGetPriceForFiat({
  String? promoCode,
}) {
  final urlParams =
      promoCode != null && promoCode.isNotEmpty ? '?promoCode=$promoCode' : '';

  return urlParams;
}

class DontUsePaymentService implements PaymentService {
  @override
  late ArDriveHTTP httpClient;

  @override
  Future<BigInt> getPriceForBytes({required int byteSize}) =>
      throw UnimplementedError();

  @override
  Future<BigInt> getBalance({required Wallet wallet}) =>
      throw UnimplementedError();

  @override
  Future<PaymentModel> getPaymentIntent({
    required Wallet wallet,
    required double amount,
    String currency = 'usd',
    String? promoCode,
  }) async {
    throw UnimplementedError();
  }

  @override
  Uri get turboPaymentUri => throw UnimplementedError();

  @override
  bool get useTurboPayment => false;

  @override
  Future<PriceForFiat> getPriceForFiat({
    required wallet,
    required double amount,
    required String currency,
    String? promoCode,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<String>> getSupportedCountries() {
    throw UnimplementedError();
  }
}

class TurboUserNotFound implements Exception {
  TurboUserNotFound();
}

class PaymentServiceException implements Exception {
  final String message;

  PaymentServiceException([this.message = '']);
}

class PaymentServiceInvalidPromoCode implements PaymentServiceException {
  final String? promoCode;

  PaymentServiceInvalidPromoCode({required this.promoCode});

  @override
  String get message => 'Invalid promo code: "$promoCode"';
}

class PriceForFiat extends Equatable {
  final BigInt winc;
  final int? actualPaymentAmount;
  final int? quotedPaymentAmount;
  final List<Adjustment> adjustments;

  String? get humanReadableDiscountPercentage {
    if (adjustments.isEmpty) {
      return null;
    }

    return adjustments.first.humanReadableDiscountPercentage;
  }

  double? get promoDiscountFactor {
    if (adjustments.isEmpty) {
      return null;
    }

    final adjustmentMagnitude = adjustments.first.operatorMagnitude;

    // Multiplying by 100 and then dividing by 100 is a workaround for
    /// floating point precision issues.
    final factor = (100 - (adjustmentMagnitude * 100)) / 100;

    return factor;
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
