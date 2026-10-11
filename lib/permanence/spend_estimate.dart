/// Turbo credits a wallet has used, from its top-ups and what is left.
///
/// Everything credited - bought, granted or gifted - minus [balanceWinc],
/// which must be the wallet's *own* credits (Turbo's `controlledWinc`), not
/// what it can spend: that includes credits other wallets have shared with
/// it, which arrived with no top-up of their own and would make the wallet
/// look as if it had used less. Exact, with no price in it.
///
/// It counts every use of the wallet's own credits, so it includes ArNS
/// names bought with them and credits it shared that the other wallet has
/// spent. Never below zero.
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
