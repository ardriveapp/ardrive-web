import 'dart:convert';

import 'package:ardrive/turbo/topup/models/payment_model.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/turbo_utils.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:arweave/arweave.dart';
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

  Future<BigInt> getPriceForFiat({
    required int amount,
    required String currency,
  }) async {
    final acceptedStatusCodes = [200, 202, 204];

    final result = await httpClient.get(
      url: '$turboPaymentUri/v1/price/$currency/$amount',
    );

    if (!acceptedStatusCodes.contains(result.statusCode)) {
      throw PaymentServiceException(
        'Turbo price fetch failed with status code ${result.statusCode}',
      );
    }

    final price = BigInt.parse((json.decode(result.data)['winc']));

    return price;
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
    required int amount,
    String currency = 'usd',
  }) async {
    final nonce = const Uuid().v4();
    final walletAddress = await wallet.getAddress();
    final publicKey = await wallet.getOwner();
    final signature = await signNonceAndData(
      nonce: nonce,
      wallet: wallet,
    );

    final result = await httpClient.get(
      url:
          '$turboPaymentUri/v1/top-up/payment-intent/$walletAddress/$currency/$amount',
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
    required int amount,
    String currency = 'usd',
  }) async {
    throw UnimplementedError();
  }

  @override
  Uri get turboPaymentUri => throw UnimplementedError();

  @override
  bool get useTurboPayment => false;

  @override
  Future<BigInt> getPriceForFiat({
    required int amount,
    required String currency,
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
