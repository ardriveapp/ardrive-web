/// One completed Turbo top-up, as `GET /v1/account/payments` reports it.
class TurboTopUp {
  const TurboTopUp({
    required this.wincCredited,
    required this.usd,
    required this.isGrant,
  });

  /// Reads one row of the payment history.
  ///
  /// A crypto row carries the USD value captured when the credits landed. A
  /// fiat row carries what was charged, in the currency's smallest unit -
  /// cents for dollars - and is converted with [usdPerUnit], which maps a
  /// lower-case currency code to what one whole unit of it is worth in USD.
  /// A currency that cannot be converted gives a row with no USD value.
  ///
  /// Credits nobody here paid for are a grant: a gift, or credits an admin
  /// added (`paymentProvider: admin`, or nothing charged).
  factory TurboTopUp.fromJson(
    Map<String, dynamic> json, {
    required Map<String, double> usdPerUnit,
  }) {
    final winc = BigInt.tryParse('${json['wincCredited']}') ?? BigInt.zero;

    if (json['type'] == 'crypto') {
      return TurboTopUp(
        wincCredited: winc,
        usd: double.tryParse('${json['usdEquivalent']}'),
        isGrant: false,
      );
    }

    final currency = '${json['currencyType']}'.toLowerCase();
    final amount = double.tryParse('${json['paymentAmount']}');
    final provider = '${json['paymentProvider']}'.toLowerCase();
    final isGrant = json['giftMessage'] != null ||
        provider == 'admin' ||
        (amount != null && amount <= 0);

    if (isGrant) {
      return TurboTopUp(wincCredited: winc, usd: 0, isGrant: true);
    }

    final rate = usdPerUnit[currency];
    final minorUnits = _zeroDecimalCurrencies.contains(currency) ? 1 : 100;

    return TurboTopUp(
      wincCredited: winc,
      usd: amount == null || rate == null ? null : amount / minorUnits * rate,
      isGrant: false,
    );
  }

  final BigInt wincCredited;

  /// What the credits cost, in US dollars: zero for a grant, null when it
  /// cannot be known.
  final double? usd;

  /// Credits that arrived without being bought: a gift, or an admin grant.
  final bool isGrant;

  /// Currencies Stripe charges in whole units, with no cents.
  static const _zeroDecimalCurrencies = {'jpy'};
}

/// What the wallet has spent on storage, as far as its top-ups can tell.
class SpendEstimate {
  const SpendEstimate({
    required this.usd,
    required this.paidCount,
    required this.grantCount,
  });

  final double usd;

  /// Top-ups that were bought, with a known price.
  final int paidCount;

  /// Top-ups that were given rather than bought.
  final int grantCount;
}

/// Estimates what a wallet has spent from its Turbo top-ups and what is left.
///
/// Turbo records credits going in, not what each upload cost, so this takes
/// the credits used - everything credited, bought or granted, minus the
/// current [balanceWinc] - and counts the bought share of them at what was
/// paid. A wallet whose credits were all granted has spent nothing.
///
/// Null when there is no top-up to go on: a wallet that uploaded for free or
/// paid in AR directly. Rows whose price cannot be known are left out.
///
/// It reads high when credits went to something other than storage - an ArNS
/// name, credits shared to another wallet - and it does not see uploads paid
/// directly in AR.
SpendEstimate? estimateSpend({
  required List<TurboTopUp> topUps,
  required BigInt balanceWinc,
}) {
  final known = topUps
      .where((t) => t.usd != null && t.wincCredited > BigInt.zero)
      .toList();

  if (known.isEmpty) {
    return null;
  }

  final paid = known.where((t) => !t.isGrant);
  final creditedWinc =
      known.fold(BigInt.zero, (sum, t) => sum + t.wincCredited);
  final paidUsd = paid.fold(0.0, (sum, t) => sum + t.usd!);

  var usedWinc = creditedWinc - balanceWinc;
  if (usedWinc < BigInt.zero) {
    usedWinc = BigInt.zero;
  }

  // What is left is taken to be bought and granted credits alike, in the
  // proportion they came in.
  return SpendEstimate(
    usd: paidUsd * (usedWinc / creditedWinc),
    paidCount: paid.length,
    grantCount: known.length - paid.length,
  );
}
