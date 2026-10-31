import 'dart:convert';

import 'package:ardrive/permanence/permanence_panel.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/utils/get_signature_headers_for_turbo.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockHttp extends Mock implements ArDriveHTTP {}

class _MockSigner extends Mock implements TurboSignatureHeadersManager {}

class _MockWallet extends Mock implements Wallet {}

class _MockPaymentService extends Mock implements PaymentService {}

void main() {
  late _MockHttp http;
  late _MockSigner signer;
  late _MockWallet wallet;
  late PaymentService service;

  setUpAll(() => registerFallbackValue(_MockWallet()));

  setUp(() {
    http = _MockHttp();
    signer = _MockSigner();
    wallet = _MockWallet();
    service = PaymentService(
      turboPaymentUri: Uri.parse('https://payment.example'),
      httpClient: http,
      turboSignatureHeadersManager: signer,
    );
    when(() => signer.getSignatureHeaders(wallet: any(named: 'wallet')))
        .thenAnswer((_) async => {'x-signature': 'sig'});
  });

  /// A history of [pages] pages, each of one row, the last saying there is
  /// no more.
  void stubPages(int pages) {
    var served = 0;
    when(() => http.get(
          url: any(named: 'url'),
          headers: any(named: 'headers'),
        )).thenAnswer((_) async {
      served++;
      return ArDriveHTTPResponse(
        data: jsonEncode({
          'payments': [
            {'type': 'fiat', 'wincCredited': '1'}
          ],
          'hasMore': served < pages,
          'cursor': served < pages ? 'page-$served' : null,
        }),
        statusCode: 200,
        retryAttempts: 0,
      );
    });
  }

  group('getPaymentHistory', () {
    test('reads every page, and says it has all of them', () async {
      stubPages(3);

      final history = await service.getPaymentHistory(wallet: wallet);

      expect(history.payments, hasLength(3));
      expect(history.complete, isTrue);
    });

    test('a history longer than it reads says it is not complete', () async {
      // Cut short is not smaller: a reader of the rows alone would take 2
      // pages for the whole history.
      stubPages(5);

      final history =
          await service.getPaymentHistory(wallet: wallet, maxPages: 2);

      expect(history.payments, hasLength(2));
      expect(history.complete, isFalse);
      verify(() => http.get(
            url: any(named: 'url'),
            headers: any(named: 'headers'),
          )).called(2);
    });
  });

  group('a refused signature', () {
    ArDriveHTTPException refused(int code) => ArDriveHTTPException(
          retryAttempts: 0,
          exception: Exception('refused'),
          statusCode: code,
        );

    ArDriveHTTPResponse ok() => ArDriveHTTPResponse(
          data: jsonEncode({'payments': [], 'hasMore': false}),
          statusCode: 200,
          retryAttempts: 0,
        );

    for (final code in [401, 403]) {
      test('$code drops the cached headers and retries once, fresh', () async {
        var sent = 0;
        final used = <Object?>[];
        when(() => signer.getSignatureHeaders(wallet: any(named: 'wallet')))
            .thenAnswer((_) async => {'x-signature': 'sig${used.length}'});
        when(() => http.get(
              url: any(named: 'url'),
              headers: any(named: 'headers'),
            )).thenAnswer((i) async {
          used.add(i.namedArguments[#headers]);
          if (sent++ == 0) throw refused(code);
          return ok();
        });

        final page = await service.getPaymentHistoryPage(wallet: wallet);

        expect(page.payments, isEmpty);
        expect(used, hasLength(2));
        expect(used[0], isNot(used[1]));
        verify(() => signer.clearCache()).called(1);
      });
    }

    test('a second refusal is the caller\'s, not retried again', () async {
      when(() => http.get(
            url: any(named: 'url'),
            headers: any(named: 'headers'),
          )).thenThrow(refused(401));

      await expectLater(
        service.getPaymentHistoryPage(wallet: wallet),
        throwsA(isA<ArDriveHTTPException>()),
      );
      verify(() => http.get(
            url: any(named: 'url'),
            headers: any(named: 'headers'),
          )).called(2);
    });

    test('other failures are not retried and keep the cache', () async {
      when(() => http.get(
            url: any(named: 'url'),
            headers: any(named: 'headers'),
          )).thenThrow(refused(500));

      await expectLater(
        service.getPaymentHistoryPage(wallet: wallet),
        throwsA(isA<ArDriveHTTPException>()),
      );
      verify(() => http.get(
            url: any(named: 'url'),
            headers: any(named: 'headers'),
          )).called(1);
      verifyNever(() => signer.clearCache());
    });

    test('the existing getPaymentHistory retries too', () async {
      var sent = 0;
      when(() => http.get(
            url: any(named: 'url'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async {
        if (sent++ == 0) throw refused(401);
        return ok();
      });

      final history = await service.getPaymentHistory(wallet: wallet);

      expect(history.complete, isTrue);
      verify(() => signer.clearCache()).called(1);
    });
  });

  test('a history cut short gives no figure at all', () async {
    final payments = _MockPaymentService();
    when(() => payments.getPaymentHistory(wallet: any(named: 'wallet')))
        .thenAnswer((_) async => const TurboPaymentHistory(
              payments: [
                {'type': 'crypto', 'wincCredited': '100'}
              ],
              complete: false,
            ));

    final lookup = await loadCreditsSpent(
      paymentService: payments,
      wallet: wallet,
    );

    expect(lookup.tooMany, isTrue);
    expect(lookup.creditsWinc, isNull);
    verifyNever(
        () => payments.getBalanceAndPaidBy(wallet: any(named: 'wallet')));
  });

  test(
      'credits used are what came in less the wallet\'s own credits, not '
      'what it can spend', () async {
    // 1,000 credited, 250 of its own left, and 4,000 more it can spend that
    // another wallet shared with it - with no top-up of their own.
    final payments = _MockPaymentService();
    when(() => payments.getPaymentHistory(wallet: any(named: 'wallet')))
        .thenAnswer((_) async => const TurboPaymentHistory(
              payments: [
                {'type': 'fiat', 'wincCredited': '1000'}
              ],
              complete: true,
            ));
    when(() => payments.getBalanceAndPaidBy(wallet: any(named: 'wallet')))
        .thenAnswer((_) async => TurboBalanceInterface(
              balance: BigInt.from(4250),
              paidBy: ['sharer'],
              controlledWinc: BigInt.from(250),
            ));

    final lookup = await loadCreditsSpent(
      paymentService: payments,
      wallet: wallet,
    );

    expect(lookup.creditsWinc, BigInt.from(750));
  });
}
