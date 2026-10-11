/// Turbo credits a wallet has used, from its top-ups and what is left.
///
/// Everything credited - bought, granted or gifted - minus the current
/// [balanceWinc]. Exact, with no price in it: credits are what a wallet holds
/// and spends, whatever was paid for them.
///
/// It counts every use of credits, so it includes ArNS names bought with
/// them and credits shared with other wallets. Never below zero: credits
/// shared *to* this wallet sit in its balance without a top-up of its own.
///
/// [payments] are rows of `GET /v1/account/payments`.
BigInt creditsUsed({
  required List<Map<String, dynamic>> payments,
  required BigInt balanceWinc,
}) {
  final credited = payments.fold(
    BigInt.zero,
    (sum, row) =>
        sum + (BigInt.tryParse('${row['wincCredited']}') ?? BigInt.zero),
  );
  final used = credited - balanceWinc;

  return used < BigInt.zero ? BigInt.zero : used;
}
