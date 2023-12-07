// unit tests for PaymentService

import 'dart:io';

import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/topup/models/payment_model.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

const String fakeUrl = 'https://fakeurl.com';
const String fakePromoCode = 'TOTEM';
const String currency = 'USD';
const double amount = 1;
const int byteSize = 1000;

class ArDriveHTTPMock extends Mock implements ArDriveHTTP {}

void main() {
  late PaymentService paymentService;
  late ArDriveHTTPMock httpClient;
  late Wallet wallet;
  late String walletAddress;

  group('PaymentService class', () {
    setUp(() async {
      httpClient = ArDriveHTTPMock();
      paymentService = PaymentService(
        turboPaymentUri: Uri.parse(fakeUrl),
        httpClient: httpClient,
      );
      wallet = getTestWallet();
      walletAddress = await wallet.getAddress();

      when(() => httpClient.get(url: '$fakeUrl/v1/price/bytes/$byteSize'))
          .thenAnswer(
        (_) async => ArDriveHTTPResponse(
          statusCode: HttpStatus.ok,
          data: '{"winc": "1000000000000"}',
          retryAttempts: 0,
        ),
      );

      when(
        () => httpClient.get(
          url: '$fakeUrl/v1/price/$currency/$amount',
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(
        (_) async => ArDriveHTTPResponse(
          statusCode: HttpStatus.ok,
          data: '{"winc": "1000000000000"}',
          retryAttempts: 0,
        ),
      );

      when(
        () => httpClient.get(
          url:
              '$fakeUrl/v1/price/fiat/$currency/$amount?promoCode=$fakePromoCode',
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(
        (_) async => ArDriveHTTPResponse(
          statusCode: HttpStatus.ok,
          data: '{"winc": "1000000000000"}',
          retryAttempts: 0,
        ),
      );

      when(
        () => httpClient.get(
          url: '$fakeUrl/v1/balance',
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(
        (_) async => ArDriveHTTPResponse(
          statusCode: HttpStatus.ok,
          data: '{"winc": "1000000000000"}',
          retryAttempts: 0,
        ),
      );

      when(
        () => httpClient.get(
          url:
              '$fakeUrl/v1/top-up/payment-intent/$walletAddress/$currency/$amount',
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(
        (_) async => ArDriveHTTPResponse(
          statusCode: HttpStatus.ok,
          data:
              '{"paymentSession": {"id": "session1", "client_secret": "secret1"}, "topUpQuote": {"topUpQuoteId": "quote1", "destinationAddress": "address1", "destinationAddressType": "type1", "paymentAmount": 100, "quotedPaymentAmount": 90, "currencyType": "USD", "winstonCreditAmount": "1000", "quoteExpirationDate": "2022-12-31", "paymentProvider": "provider1"}, "adjustments": [{"name": "adjustment1", "description": "description1", "operatorMagnitude": 1.5, "operator": "+", "adjustmentAmount": 10, "maxDiscount": 5}]}',
          retryAttempts: 0,
        ),
      );

      when(
        () => httpClient.get(
          url:
              '$fakeUrl/v1/top-up/payment-intent/$walletAddress/$currency/$amount?promoCode=$fakePromoCode',
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(
        (_) async => ArDriveHTTPResponse(
          statusCode: HttpStatus.ok,
          data:
              '{"paymentSession": {"id": "session1", "client_secret": "secret1"}, "topUpQuote": {"topUpQuoteId": "quote1", "destinationAddress": "address1", "destinationAddressType": "type1", "paymentAmount": 100, "quotedPaymentAmount": 90, "currencyType": "USD", "winstonCreditAmount": "1000", "quoteExpirationDate": "2022-12-31", "paymentProvider": "provider1"}, "adjustments": [{"name": "adjustment1", "description": "description1", "operatorMagnitude": 1.5, "operator": "+", "adjustmentAmount": 10, "maxDiscount": 5}]}',
          retryAttempts: 0,
        ),
      );

      when(
        () => httpClient.get(
          url: '$fakeUrl/v1/countries',
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(
        (_) async => ArDriveHTTPResponse(
          statusCode: HttpStatus.ok,
          data: '["US", "CA"]',
          retryAttempts: 0,
        ),
      );
    });

    group('getPriceForBytes method', () {
      test('should return a BigInt', () async {
        final result =
            await paymentService.getPriceForBytes(byteSize: byteSize);
        expect(result, isA<BigInt>());

        when(() => httpClient.get(url: '$fakeUrl/v1/price/bytes/$byteSize'))
            .thenAnswer(
          (_) async => ArDriveHTTPResponse(
            statusCode: 202,
            data: '{"winc": "1000000000000"}',
            retryAttempts: 0,
          ),
        );
        final result2 =
            await paymentService.getPriceForBytes(byteSize: byteSize);
        expect(result2, isA<BigInt>());

        when(() => httpClient.get(url: '$fakeUrl/v1/price/bytes/$byteSize'))
            .thenAnswer(
          (_) async => ArDriveHTTPResponse(
            statusCode: 204,
            data: '{"winc": "1000000000000"}',
            retryAttempts: 0,
          ),
        );
        final result3 =
            await paymentService.getPriceForBytes(byteSize: byteSize);
        expect(result3, isA<BigInt>());
      });

      test('should throw an exception if the status code is not 200, 202, 204',
          () async {
        when(() => httpClient.get(url: '$fakeUrl/v1/price/bytes/$byteSize'))
            .thenAnswer(
          (_) async => ArDriveHTTPResponse(
            statusCode: HttpStatus.badRequest,
            data: null,
            retryAttempts: 0,
          ),
        );
        expect(
          () async => await paymentService.getPriceForBytes(byteSize: byteSize),
          throwsException,
        );
      });
    });

    group('getPriceForFiat method', () {
      test('should return a PriceForFiat object', () async {
        final result = await paymentService.getPriceForFiat(
          amount: amount,
          currency: currency,
          wallet: wallet,
        );
        expect(result, isA<PriceForFiat>());
      });

      test(
          'should throw a PaymentServiceInvalidPromoCode exception if the status code is bad request',
          () async {
        when(
          () => httpClient.get(
            url: '$fakeUrl/v1/price/$currency/$amount?promoCode=$fakePromoCode',
            headers: any(named: 'headers'),
          ),
        ).thenThrow(
          ArDriveHTTPException(
            statusCode: 400,
            retryAttempts: 0,
            exception: Exception('400'),
          ),
        );
        expect(
          () async => await paymentService.getPriceForFiat(
            amount: amount,
            currency: currency,
            wallet: wallet,
            promoCode: fakePromoCode,
          ),
          throwsA(isA<PaymentServiceInvalidPromoCode>()),
        );
      });

      test(
          'should throw a PaymentServiceException exception if the status code is not 400',
          () async {
        when(
          () => httpClient.get(
            url: '$fakeUrl/v1/price/$currency/$amount?promoCode=$fakePromoCode',
            headers: any(named: 'headers'),
          ),
        ).thenThrow(
          ArDriveHTTPException(
            statusCode: 500,
            retryAttempts: 0,
            exception: Exception('500'),
          ),
        );
        expect(
          () async => await paymentService.getPriceForFiat(
            amount: amount,
            currency: currency,
            wallet: wallet,
            promoCode: fakePromoCode,
          ),
          throwsA(isA<PaymentServiceException>()),
        );
      });
    });

    group('getBalance method', () {
      test('should return a BigInt', () async {
        final result = await paymentService.getBalance(wallet: wallet);
        expect(result, isA<BigInt>());
      });

      test(
          'should throw a TurboUserNotFound exception if the status code is 404',
          () async {
        when(
          () => httpClient.get(
            url: '$fakeUrl/v1/balance',
            headers: any(named: 'headers'),
          ),
        ).thenThrow(ArDriveHTTPException(
          statusCode: 404,
          retryAttempts: 0,
          exception: Exception('404'),
        ));
        expect(
          () async => await paymentService.getBalance(wallet: wallet),
          throwsA(isA<TurboUserNotFound>()),
        );
      });

      test('should throw an exception if the status code is not 404', () async {
        when(
          () => httpClient.get(
            url: '$fakeUrl/v1/balance',
            headers: any(named: 'headers'),
          ),
        ).thenThrow(ArDriveHTTPException(
          statusCode: 500,
          retryAttempts: 0,
          exception: Exception('500'),
        ));
        expect(
          () async => await paymentService.getBalance(wallet: wallet),
          throwsA(isA<ArDriveHTTPException>()),
        );
      });
    });
  });

  group('getPaymentIntent method', () {
    test('should return a PaymentModel object', () async {
      final result = await paymentService.getPaymentIntent(
        wallet: wallet,
        amount: amount,
        currency: currency,
      );
      expect(result, isA<PaymentModel>());
    });

    test('should throw an exception if the request fails', () async {
      when(
        () => httpClient.get(
          url:
              '$fakeUrl/v1/top-up/payment-intent/$walletAddress/$currency/$amount?promoCode=$fakePromoCode',
          headers: any(named: 'headers'),
        ),
      ).thenThrow(
        ArDriveHTTPException(
          statusCode: 404,
          retryAttempts: 0,
          exception: Exception('404'),
        ),
      );
      expect(
        () async => await paymentService.getPaymentIntent(
          wallet: wallet,
          amount: amount,
          currency: currency,
          promoCode: fakePromoCode,
        ),
        throwsException,
      );
    });
  });

  group('getSupportedCountries method', () {
    test('should return a list of countries', () async {
      final result = await paymentService.getSupportedCountries();
      expect(result, isA<List<String>>());
    });

    test('should throw an exception if the request fails', () async {
      when(
        () => httpClient.get(
          url: '$fakeUrl/v1/countries',
          headers: any(named: 'headers'),
        ),
      ).thenThrow(
        ArDriveHTTPException(
          statusCode: 404,
          retryAttempts: 0,
          exception: Exception('404'),
        ),
      );
      expect(
        () async => await paymentService.getSupportedCountries(),
        throwsException,
      );
    });
  });
}
