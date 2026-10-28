import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/models/crypto_quote.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 5 USDC.
  CryptoTopupConfirmation confirmation({double? walletUsdc}) =>
      CryptoTopupConfirmation(
        token: CryptoToken.usdcBase,
        quote: CryptoQuote(
          token: CryptoToken.usdcBase,
          tokenAmount: BigInt.from(5000000),
          wincAmount: BigInt.parse('933000000000'),
          creditsDisplay: 0.9330,
          estimatedStorageGiB: 0.0614,
          usdValue: 5,
          networkFeeUsd: 0.01,
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        ),
        fromAddress: '0x6163dC89C5399d9De9E2c8aA0AA506C0bFC3881B',
        toAddress: 'Turbo Gateway',
        networkState: NetworkState.correct,
        tokenBalance: walletUsdc,
      );

  test('a wallet holding less than the payment cannot confirm', () {
    final state = confirmation(walletUsdc: 2);

    expect(state.hasInsufficientBalance, isTrue);
    expect(state.canConfirm, isFalse);
  });

  test('a wallet holding the payment can confirm', () {
    final state = confirmation(walletUsdc: 20);

    expect(state.hasInsufficientBalance, isFalse);
    expect(state.canConfirm, isTrue);
  });

  test('an unknown balance does not block: the wallet still refuses', () {
    final state = confirmation();

    expect(state.hasInsufficientBalance, isFalse);
    expect(state.canConfirm, isTrue);
  });
}
