import 'package:ardrive/permanence/spend_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const usdPerUnit = {'usd': 1.0, 'eur': 1.1, 'jpy': 0.0067};

  TurboTopUp row(Map<String, dynamic> json) =>
      TurboTopUp.fromJson(json, usdPerUnit: usdPerUnit);

  group('reading a payment history row', () {
    test('a card payment in dollars is in cents', () {
      final topUp = row({
        'type': 'fiat',
        'wincCredited': '1000',
        'paymentAmount': '2500',
        'currencyType': 'usd',
        'giftMessage': null,
      });

      expect(topUp.usd, 25.0);
      expect(topUp.wincCredited, BigInt.from(1000));
      expect(topUp.isGift, isFalse);
    });

    test('a card payment in another currency is converted to dollars', () {
      final topUp = row({
        'type': 'fiat',
        'wincCredited': '1000',
        'paymentAmount': '1000',
        'currencyType': 'EUR',
        'giftMessage': null,
      });

      expect(topUp.usd, closeTo(11.0, 1e-9));
    });

    test('yen has no cents', () {
      final topUp = row({
        'type': 'fiat',
        'wincCredited': '1000',
        'paymentAmount': '3000',
        'currencyType': 'jpy',
        'giftMessage': null,
      });

      expect(topUp.usd, closeTo(20.1, 1e-9));
    });

    test('a currency that cannot be converted has no dollar value', () {
      final topUp = row({
        'type': 'fiat',
        'wincCredited': '1000',
        'paymentAmount': '1000',
        'currencyType': 'xyz',
        'giftMessage': null,
      });

      expect(topUp.usd, isNull);
    });

    test('a crypto top-up carries its dollar value from when it landed', () {
      final topUp = row({
        'type': 'crypto',
        'wincCredited': '1000',
        'usdEquivalent': '12.34',
      });

      expect(topUp.usd, 12.34);
      expect(topUp.isGift, isFalse);
    });

    test('a row with a gift message is a gift', () {
      final topUp = row({
        'type': 'fiat',
        'wincCredited': '1000',
        'paymentAmount': '1000',
        'currencyType': 'usd',
        'giftMessage': 'happy birthday',
      });

      expect(topUp.isGift, isTrue);
    });
  });

  group('estimating what was spent', () {
    TurboTopUp paid(int winc, double usd) =>
        TurboTopUp(wincCredited: BigInt.from(winc), usd: usd, isGift: false);

    test('credits used, at the average price paid for them', () {
      // 1,000 credits for $10 and 1,000 for $30: $0.02 each on average.
      // 500 are left, so 1,500 were used.
      final estimate = estimateSpend(
        topUps: [paid(1000, 10), paid(1000, 30)],
        balanceWinc: BigInt.from(500),
      );

      expect(estimate!.usd, closeTo(30.0, 1e-9));
      expect(estimate.topUpCount, 2);
    });

    test('nothing used is nothing spent', () {
      final estimate = estimateSpend(
        topUps: [paid(1000, 10)],
        balanceWinc: BigInt.from(1000),
      );

      expect(estimate!.usd, 0);
    });

    test('a balance above what was bought does not make spending negative', () {
      // Gifted or shared credits on top of what was paid for.
      final estimate = estimateSpend(
        topUps: [paid(1000, 10)],
        balanceWinc: BigInt.from(5000),
      );

      expect(estimate!.usd, 0);
    });

    test('gifts and rows with no price are left out', () {
      final estimate = estimateSpend(
        topUps: [
          paid(1000, 10),
          TurboTopUp(
            wincCredited: BigInt.from(9000),
            usd: 90,
            isGift: true,
          ),
          TurboTopUp(
            wincCredited: BigInt.from(9000),
            usd: null,
            isGift: false,
          ),
        ],
        balanceWinc: BigInt.zero,
      );

      expect(estimate!.usd, 10);
      expect(estimate.topUpCount, 1);
    });

    test('no paid top-ups is no estimate, not zero', () {
      // Free uploads, or uploads paid in AR directly: nothing to go on.
      expect(estimateSpend(topUps: [], balanceWinc: BigInt.zero), isNull);
    });
  });
}
