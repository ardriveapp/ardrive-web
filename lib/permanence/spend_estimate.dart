/// One completed Turbo top-up, as `GET /v1/account/payments` reports it.
class TurboTopUp {
  const TurboTopUp({
    required this.wincCredited,
    required this.usd,
    required this.isGift,
  });

  /// Reads one row of the payment history.
  ///
  /// A crypto row carries the USD value captured when the credits landed. A
  /// fiat row carries what was charged, in the currency's smallest unit -
  /// cents for dollars - and is converted with [usdPerUnit], which maps a
  /// lower-case currency code to what one whole unit of it is worth in USD.
  /// A currency that cannot be converted gives a row with no USD value.
  factory TurboTopUp.fromJson(
    Map<String, dynamic> json, {
    required Map<String, double> usdPerUnit,
  }) {
    final winc = BigInt.tryParse('${json['wincCredited']}') ?? BigInt.zero;

    if (json['type'] == 'crypto') {
      return TurboTopUp(
        wincCredited: winc,
        usd: double.tryParse('${json['usdEquivalent']}'),
        isGift: false,
      );
    }

    final currency = '${json['currencyType']}'.toLowerCase();
    final amount = double.tryParse('${json['paymentAmount']}');
    final rate = usdPerUnit[currency];
    final minorUnits = _zeroDecimalCurrencies.contains(currency) ? 1 : 100;

    return TurboTopUp(
      wincCredited: winc,
      usd: amount == null || rate == null ? null : amount / minorUnits * rate,
      isGift: json['giftMessage'] != null,
    );
  }

  final BigInt wincCredited;

  /// What the credits cost, in US dollars. Null when it cannot be known.
  final double? usd;

  /// Credits that arrived as a gift, which this wallet did not pay for.
  final bool isGift;

  /// Currencies Stripe charges in whole units, with no cents.
  static const _zeroDecimalCurrencies = {'jpy'};
}

/// What the wallet has spent on storage, as far as its top-ups can tell.
class SpendEstimate {
  const SpendEstimate({required this.usd, required this.topUpCount});

  final double usd;

  /// The paid top-ups the figure is built from.
  final int topUpCount;
}

/// Estimates what a wallet has spent from its Turbo top-ups and what is left.
///
/// Turbo records money going in, not what each upload cost, so this is
/// credits used - bought minus the current [balanceWinc] - at the wallet's
/// average price per credit. Gifts are left out: nobody here paid for them.
/// Null when no paid top-up has a known price, which is a wallet that uploaded
/// for free or paid in AR directly: there is nothing to estimate from.
///
/// It reads high when credits went to something other than storage - an ArNS
/// name, credits shared to another wallet - and it does not see uploads paid
/// directly in AR.
SpendEstimate? estimateSpend({
  required List<TurboTopUp> topUps,
  required BigInt balanceWinc,
}) {
  final paid = topUps
      .where((t) => !t.isGift && t.usd != null && t.wincCredited > BigInt.zero);

  if (paid.isEmpty) {
    return null;
  }

  final paidWinc = paid.fold(BigInt.zero, (sum, t) => sum + t.wincCredited);
  final paidUsd = paid.fold(0.0, (sum, t) => sum + t.usd!);

  var spentWinc = paidWinc - balanceWinc;
  if (spentWinc < BigInt.zero) {
    spentWinc = BigInt.zero;
  }

  return SpendEstimate(
    usd: paidUsd * (spentWinc / paidWinc),
    topUpCount: paid.length,
  );
}
