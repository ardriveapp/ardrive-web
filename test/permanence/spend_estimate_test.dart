import 'package:ardrive/permanence/spend_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const usdPerUnit = {'usd': 1.0, 'eur': 1.1, 'jpy': 0.0067};

  TurboTopUp row(Map<String, dynamic> json) =>
      TurboTopUp.fromJson(json, usdPerUnit: usdPerUnit);

  Map<String, dynamic> card({
    String amount = '2500',
    String currency = 'usd',
    String provider = 'stripe',
    String? giftMessage,
  }) =>
      {
        'type': 'fiat',
        'wincCredited': '1000',
        'paymentAmount': amount,
        'currencyType': currency,
        'paymentProvider': provider,
        'giftMessage': giftMessage,
      };

  group('reading a payment history row', () {
    test('a card payment in dollars is in cents', () {
      final topUp = row(card());

      expect(topUp.usd, 25.0);
      expect(topUp.wincCredited, BigInt.from(1000));
      expect(topUp.isGrant, isFalse);
    });

    test('a card payment in another currency is converted to dollars', () {
      expect(
          row(card(amount: '1000', currency: 'EUR')).usd, closeTo(11.0, 1e-9));
    });

    test('yen has no cents', () {
      expect(
          row(card(amount: '3000', currency: 'jpy')).usd, closeTo(20.1, 1e-9));
    });

    test('a currency that cannot be converted has no dollar value', () {
      expect(row(card(amount: '1000', currency: 'xyz')).usd, isNull);
    });

    test('a crypto top-up carries its dollar value from when it landed', () {
      final topUp = row({
        'type': 'crypto',
        'wincCredited': '1000',
        'usdEquivalent': '12.34',
      });

      expect(topUp.usd, 12.34);
      expect(topUp.isGrant, isFalse);
    });

    test('credits an admin granted were not bought', () {
      // What the console calls "Credit grant via admin".
      final topUp = row(card(provider: 'admin', currency: 'usd'));

      expect(topUp.isGrant, isTrue);
      expect(topUp.usd, 0);
    });

    test('nothing charged is a grant, whatever the provider', () {
      expect(row(card(amount: '0')).isGrant, isTrue);
    });

    test('a gift is a grant', () {
      expect(row(card(giftMessage: 'happy birthday')).isGrant, isTrue);
    });
  });

  group('estimating what was spent', () {
    TurboTopUp paid(int winc, double usd) =>
        TurboTopUp(wincCredited: BigInt.from(winc), usd: usd, isGrant: false);
    TurboTopUp granted(int winc) =>
        TurboTopUp(wincCredited: BigInt.from(winc), usd: 0, isGrant: true);

    test('credits used, at the average price paid for them', () {
      // 1,000 credits for $10 and 1,000 for $30. 500 are left, so 1,500 of
      // the 2,000 were used: three quarters of the $40.
      final estimate = estimateSpend(
        topUps: [paid(1000, 10), paid(1000, 30)],
        balanceWinc: BigInt.from(500),
      );

      expect(estimate!.usd, closeTo(30.0, 1e-9));
      expect(estimate.paidCount, 2);
      expect(estimate.grantCount, 0);
    });

    test('a wallet whose credits were all granted has spent nothing', () {
      final estimate = estimateSpend(
        topUps: [granted(5000), granted(400), granted(5000)],
        balanceWinc: BigInt.from(100),
      );

      expect(estimate!.usd, 0);
      expect(estimate.paidCount, 0);
      expect(estimate.grantCount, 3);
    });

    test('bought and granted credits are used in proportion', () {
      // 1,000 bought for $10 and 1,000 granted. Half of all of it is used, so
      // half of what was bought: $5.
      final estimate = estimateSpend(
        topUps: [paid(1000, 10), granted(1000)],
        balanceWinc: BigInt.from(1000),
      );

      expect(estimate!.usd, closeTo(5.0, 1e-9));
      expect(estimate.paidCount, 1);
      expect(estimate.grantCount, 1);
    });

    test('nothing used is nothing spent', () {
      final estimate = estimateSpend(
        topUps: [paid(1000, 10)],
        balanceWinc: BigInt.from(1000),
      );

      expect(estimate!.usd, 0);
    });

    test('a balance above what came in does not make spending negative', () {
      // Credits shared from another wallet sit in the balance too.
      final estimate = estimateSpend(
        topUps: [paid(1000, 10)],
        balanceWinc: BigInt.from(5000),
      );

      expect(estimate!.usd, 0);
    });

    test('rows with no known price are left out', () {
      final estimate = estimateSpend(
        topUps: [
          paid(1000, 10),
          TurboTopUp(
            wincCredited: BigInt.from(9000),
            usd: null,
            isGrant: false,
          ),
        ],
        balanceWinc: BigInt.zero,
      );

      expect(estimate!.usd, 10);
      expect(estimate.paidCount, 1);
    });

    test('no top-ups is no estimate, not zero', () {
      // Free uploads, or uploads paid in AR directly: nothing to go on.
      expect(estimateSpend(topUps: [], balanceWinc: BigInt.zero), isNull);
    });
  });
}
