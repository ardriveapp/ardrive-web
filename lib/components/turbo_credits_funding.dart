import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/components/upload_review_dialog.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/topup/views/topup_modal.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Buys Turbo Credits for a review: Turbo's quote for an amount, the app's
/// card payment, and the balance until the credits arrive. The upload review
/// and the review of a change, such as a license, both use it.
class TurboCreditsFunding implements UploadCreditsFunding {
  TurboCreditsFunding(this.context, {required this.onRefresh});

  final BuildContext context;
  final VoidCallback onRefresh;

  /// How often, and how many times, to look for credits after a payment.
  static const _pollEvery = Duration(seconds: 2);
  static const _pollTimes = 20;

  PaymentService get _payments => context.read<PaymentService>();

  @override
  Future<BigInt> creditsFor(int amountUsd) async {
    final price = await _payments.getPriceForFiat(
      wallet: context.read<ArDriveAuth>().currentUser.wallet,
      amount: amountUsd * 100,
      currency: 'usd',
    );
    return price.winstonCredits;
  }

  @override
  Future<BigInt?> payByCard(int amountUsd) =>
      showTurboCardPayment(context, amountUsd: amountUsd);

  @override
  Future<bool> awaitCredits({required BigInt above}) async {
    final wallet = context.read<ArDriveAuth>().currentUser.wallet;
    final payments = _payments;
    // Turbo adds the credits when Stripe tells it the payment went through,
    // which can take a few seconds after the card is charged.
    for (var i = 0; i < _pollTimes; i++) {
      try {
        if (await payments.getBalance(wallet: wallet) > above) return true;
      } catch (e) {
        // A new account is unknown to Turbo until its credits land.
        logger.d('Waiting for credits: $e');
      }
      await Future.delayed(_pollEvery);
    }
    return false;
  }

  @override
  void refresh() => onRefresh();
}
