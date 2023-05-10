import 'dart:convert';

import 'package:ardrive/utils/turbo_utils.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:arweave/arweave.dart';
import 'package:uuid/uuid.dart';

const paymentUri = 'https://payment.ardrive.dev';

class PaymentService {
  ArDriveHTTP httpClient;

  PaymentService({
    required this.httpClient,
  });

  Future<BigInt> getPrice({
    required int byteSize,
  }) async {
    final acceptedStatusCodes = [200, 202, 204];
    final priceResponse = await httpClient.get(
      url: '$paymentUri/v1/price/bytes/$byteSize',
    );
    if (!acceptedStatusCodes.contains(priceResponse.statusCode)) {
      throw Exception(
        'Turbo price fetch failed with status code ${priceResponse.statusCode}',
      );
    }
    final price = BigInt.parse(priceResponse.data);
    return price;
  }

  Future<BigInt> getBalance({
    required Wallet wallet,
  }) async {
    final nonce = const Uuid().v4();
    final publicKey = await wallet.getPublicKey();
    final signature = await signNonceAndData(
      nonce: nonce,
      wallet: wallet,
    );
    final result = await httpClient.get(
      url: '$paymentUri/v1/balance',
      headers: {
        'x-nonce': nonce,
        'x-signature': signature,
        'x-public-key': publicKeyToHeader(publicKey),
      },
    );

    if (result.data == 'User not found') {
      throw TurboUserNotFound();
    }

    return BigInt.parse(result.data);
  }

  Future topUp({
    required Wallet wallet,
    required BigInt amount,
    String currency = 'usd',
  }) async {
    final nonce = const Uuid().v4();
    final walletAddress = await wallet.getAddress();
    final publicKey = await wallet.getPublicKey();
    final signature = await signNonceAndData(
      nonce: nonce,
      wallet: wallet,
    );

    final result = await httpClient.get(
      url:
          '$paymentUri/v1/top-up/payment-BigIntent/$walletAddress/$currency/$amount',
      headers: {
        'x-nonce': nonce,
        'x-signature': signature,
        'x-public-key': publicKeyToHeader(publicKey),
      },
    );

    return jsonDecode(result.data)['paymentSession'];
  }
}

class DontUsePaymentService implements PaymentService {
  @override
  late ArDriveHTTP httpClient;

  @override
  Future<BigInt> getPrice({required int byteSize}) {
    throw UnimplementedError();
  }

  @override
  Future<BigInt> getBalance({required Wallet wallet}) {
    throw UnimplementedError();
  }

  @override
  Future topUp({
    required Wallet wallet,
    required BigInt amount,
    String currency = 'usd',
  }) {
    throw UnimplementedError();
  }
}

class TurboUserNotFound implements Exception {
  TurboUserNotFound();
}
