import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/models/crypto_quote.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/views/unified/crypto_notice_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// Each stopping warning offers a primary action and a way out. Swapping one
/// event for another (take over for retry, accept for reject) changes what
/// happens to the session or the price the person pays, so every state's
/// events are pinned here.
void main() {
  final quote = CryptoQuote(
    token: CryptoToken.sol,
    tokenAmount: BigInt.one,
    wincAmount: BigInt.one,
    creditsDisplay: 1,
    estimatedStorageGiB: 1,
    usdValue: 1,
    expiresAt: DateTime(2030),
  );

  test('account changed: Start again retries, Close just closes', () {
    final n = cryptoNoticeFor(
        const CryptoTopupAccountChangedWarning(newAddress: 'a'))!;
    expect(n.action, isA<CryptoTopupRetry>());
    expect(n.closeEvent, isNull);
    expect(n.actionTitle, 'Start again');
  });

  test('session timeout: Start again retries, Close just closes', () {
    final n = cryptoNoticeFor(const CryptoTopupSessionTimeout())!;
    expect(n.action, isA<CryptoTopupRetry>());
    expect(n.closeEvent, isNull);
  });

  test('another tab: Use this tab takes over, Close just closes', () {
    final n = cryptoNoticeFor(CryptoTopupConcurrentSessionWarning(
        otherSessionStartedAt: DateTime(2026)))!;
    expect(n.action, isA<CryptoTopupTakeOverSession>());
    expect(n.closeEvent, isNull);
  });

  test('price change: Continue accepts, Close rejects', () {
    final n = cryptoNoticeFor(CryptoTopupPriceVolatilityWarning(
      originalQuote: quote,
      newQuote: quote,
      percentChange: -7.25,
    ))!;
    expect(n.action, isA<CryptoTopupPriceVolatilityAccepted>());
    expect(n.closeEvent, isA<CryptoTopupPriceVolatilityRejected>());
    expect(n.message, contains('7.3%'));
  });

  test('other states have no notice', () {
    expect(cryptoNoticeFor(const CryptoTopupInitial()), isNull);
    expect(cryptoNoticeFor(const CryptoTopupTokenSelection()), isNull);
  });
}
