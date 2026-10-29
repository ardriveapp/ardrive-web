import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/models/upload_review_summary.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// The upload review's one rule: an upload starts only when it is free, or
/// when the way it is paid for covers it.
void main() {
  UploadCostEstimate cost(int winc, {double? usd}) => UploadCostEstimate(
        pstFee: BigInt.zero,
        totalCost: BigInt.from(winc),
        totalSize: 1,
        usdUploadCost: usd,
      );

  UploadPaymentMethodInfo info({
    UploadMethod method = UploadMethod.turbo,
    FreeUploadStatus freeStatus = FreeUploadStatus.notEligible,
    int turboCost = 5875,
    int arCost = 100,
    int balance = 0,
    bool sufficientAr = false,
    bool turboPossible = true,
    bool turboUnreachable = false,
  }) =>
      UploadPaymentMethodInfo(
        uploadMethod: method,
        costEstimateTurbo: cost(turboCost, usd: 32.14),
        costEstimateAr: cost(arCost),
        hasNoTurboBalance: balance == 0,
        isTurboUploadPossible: turboPossible,
        arBalance: '0',
        sufficientArBalance: sufficientAr,
        turboCredits: '0',
        sufficentCreditsBalance: balance >= turboCost,
        freeStatus: freeStatus,
        totalSize: 1,
        turboBalanceWinc: BigInt.from(balance),
        turboUnreachable: turboUnreachable,
      );

  test('a free upload is covered, whatever the balance', () {
    final s = UploadReviewSummary.fromPaymentInfo(
        info(freeStatus: FreeUploadStatus.free));

    expect(s.isFree, isTrue);
    expect(s.isCovered, isTrue);
    expect(s.needsCredits, isFalse);
  });

  test('not free and short of credits: Add credits, never Upload', () {
    // AR is the default when credits are short, but a wallet that can't pay
    // is no choice: credits are the way.
    final s = UploadReviewSummary.fromPaymentInfo(info(
      method: UploadMethod.ar,
      freeStatus: FreeUploadStatus.allowanceUsedUp,
    ));

    expect(s.isCovered, isFalse);
    expect(s.needsCredits, isTrue);
    expect(s.method, UploadMethod.turbo);
    expect(s.overFreeAllowance, isTrue);
    expect(s.offersPaymentChoice, isFalse);
    expect(s.usdCost, 32.14);
  });

  test('credits that cover it: Upload, and what is left after', () {
    final s = UploadReviewSummary.fromPaymentInfo(info(balance: 9138));

    expect(s.isCovered, isTrue);
    expect(s.needsCredits, isFalse);
    expect(s.creditsLeftAfter, BigInt.from(3263));
  });

  test('an allowance that could not be read is not said to be used up', () {
    final s = UploadReviewSummary.fromPaymentInfo(
        info(freeStatus: FreeUploadStatus.unknown));

    expect(s.isFree, isFalse);
    expect(s.needsCredits, isTrue);
    expect(s.overFreeAllowance, isFalse);
  });

  test('no Turbo price and no wallet that can pay: no upload, a retry', () {
    final s = UploadReviewSummary.fromPaymentInfo(
        info(turboUnreachable: true, turboCost: 0, balance: 0));

    expect(s.priceUnavailable, isTrue);
    expect(s.isCovered, isFalse);
    // Not Add credits either: nobody knows what it would need.
    expect(s.needsCredits, isFalse);
  });

  test('no Turbo price, but the wallet can pay: the wallet pays', () {
    final s = UploadReviewSummary.fromPaymentInfo(info(
      turboUnreachable: true,
      sufficientAr: true,
      method: UploadMethod.ar,
    ));

    expect(s.priceUnavailable, isFalse);
    expect(s.method, UploadMethod.ar);
    expect(s.isCovered, isTrue);
  });

  test('a wallet price of zero is a price nobody read, and pays nothing', () {
    final s = UploadReviewSummary.fromPaymentInfo(
        info(sufficientAr: true, arCost: 0, method: UploadMethod.ar));

    expect(s.offersPaymentChoice, isFalse);
    expect(s.method, UploadMethod.turbo);
    expect(s.isCovered, isFalse);
  });

  test('a wallet that can pay is offered beside credits', () {
    final s = UploadReviewSummary.fromPaymentInfo(
        info(sufficientAr: true, method: UploadMethod.ar));

    expect(s.offersPaymentChoice, isTrue);
    expect(s.method, UploadMethod.ar);
    expect(s.isCovered, isTrue);
  });

  test(
      'after Turbo refused it, it is not free again, and the fresh balance '
      'decides', () {
    final refused = UploadReviewSummary.fromPaymentInfo(
      info(freeStatus: FreeUploadStatus.free, balance: 10000),
      refusedByTurbo: true,
      creditsBalance: BigInt.zero,
    );

    expect(refused.isFree, isFalse);
    expect(refused.needsCredits, isTrue);
    expect(refused.overFreeAllowance, isTrue);
    expect(refused.creditsBalance, BigInt.zero);
  });

  test('an upload only the wallet can take keeps the old selector', () {
    final s = UploadReviewSummary.fromPaymentInfo(
        info(turboPossible: false, sufficientAr: true));

    expect(s.usesLegacySelector, isTrue);
    expect(s.method, UploadMethod.ar);
    expect(s.isCovered, isTrue);
  });
}
