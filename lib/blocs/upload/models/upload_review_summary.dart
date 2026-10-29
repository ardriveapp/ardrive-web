import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:equatable/equatable.dart';

/// What the upload review says about paying for an upload, and whether it
/// lets the upload start.
///
/// One rule decides it: an upload starts only when it is free, or when the
/// way it is paid for covers it. Everything else on the review follows from
/// that: the cost shown, the notice, and whether the main button is Upload or
/// Add credits.
class UploadReviewSummary extends Equatable {
  const UploadReviewSummary({
    required this.method,
    required this.isFree,
    required this.priceUnavailable,
    required this.isCovered,
    required this.overFreeAllowance,
    required this.offersPaymentChoice,
    required this.usesLegacySelector,
    required this.creditsCost,
    required this.creditsBalance,
    required this.usdCost,
    required this.arCost,
  });

  /// How this upload would be paid for.
  final UploadMethod method;

  /// Covered by the free upload allowance.
  final bool isFree;

  /// Turbo's price or the balance could not be read, and the wallet can't pay
  /// instead. There is no upload until it can be read: a retry.
  final bool priceUnavailable;

  /// Free, or paid for by [method]. The only case in which Upload is offered.
  final bool isCovered;

  /// Says so when Turbo Credits are short: the allowance is known not to
  /// cover it, or Turbo refused it. False when the allowance could not be
  /// read, where saying it ran out would be a guess.
  final bool overFreeAllowance;

  /// The wallet can pay for this upload too, so the review offers the choice.
  final bool offersPaymentChoice;

  /// Turbo can't take this upload at all, only the wallet can, so the review
  /// keeps the payment selector it has always had for that case.
  final bool usesLegacySelector;

  /// What it costs in Turbo Credits, in winston credits.
  final BigInt creditsCost;

  /// The Turbo Credits the account can spend, in winston credits.
  final BigInt creditsBalance;

  /// [creditsCost] in US dollars, when Turbo gave a rate.
  final double? usdCost;

  /// What it costs from the wallet, in winston.
  final BigInt arCost;

  /// Paid with Turbo Credits and not covered: the review offers Add credits.
  bool get needsCredits =>
      !isFree &&
      !priceUnavailable &&
      method == UploadMethod.turbo &&
      !isCovered;

  /// Turbo Credits left once this upload is paid for.
  BigInt get creditsLeftAfter => creditsBalance - creditsCost;

  /// Reads [info] the way the review shows it.
  ///
  /// [refusedByTurbo] is for after Turbo answered 402 to the upload itself:
  /// the allowance said free and Turbo said otherwise, so it is not treated as
  /// free again. [creditsBalance] replaces the balance in [info] when it has
  /// been read since.
  factory UploadReviewSummary.fromPaymentInfo(
    UploadPaymentMethodInfo info, {
    bool refusedByTurbo = false,
    BigInt? creditsBalance,
  }) {
    final balance = creditsBalance ?? info.turboBalance;
    final creditsCost = info.costEstimateTurbo?.totalCost ?? BigInt.zero;
    final arCost = info.costEstimateAr.totalCost;
    // Zero stands in for a price that could not be read, so a wallet only
    // counts as able to pay against a real one.
    final walletCanPay = info.sufficientArBalance && arCost > BigInt.zero;
    final isFree = info.isFreeThanksToTurbo && !refusedByTurbo;

    UploadReviewSummary make({
      required UploadMethod method,
      required bool isCovered,
      bool priceUnavailable = false,
      bool offersPaymentChoice = false,
      bool usesLegacySelector = false,
    }) =>
        UploadReviewSummary(
          method: method,
          isFree: isFree,
          priceUnavailable: priceUnavailable,
          isCovered: isCovered,
          overFreeAllowance: !isFree &&
              (refusedByTurbo || info.freeStatus != FreeUploadStatus.unknown),
          offersPaymentChoice: offersPaymentChoice,
          usesLegacySelector: usesLegacySelector,
          creditsCost: creditsCost,
          creditsBalance: balance,
          usdCost: info.costEstimateTurbo?.usdUploadCost,
          arCost: arCost,
        );

    if (isFree) {
      return make(method: UploadMethod.turbo, isCovered: true);
    }

    if (!info.isTurboUploadPossible || info.costEstimateTurbo == null) {
      return make(
        method: UploadMethod.ar,
        isCovered: walletCanPay,
        usesLegacySelector: true,
      );
    }

    if (info.turboUnreachable) {
      return walletCanPay
          ? make(method: UploadMethod.ar, isCovered: true)
          : make(
              method: UploadMethod.turbo,
              isCovered: false,
              priceUnavailable: true,
            );
    }

    // Without a wallet that can pay, Turbo Credits are the only way, whatever
    // the default was.
    final method = walletCanPay ? info.uploadMethod : UploadMethod.turbo;

    return make(
      method: method,
      isCovered: method == UploadMethod.ar || balance >= creditsCost,
      offersPaymentChoice: walletCanPay,
    );
  }

  @override
  List<Object?> get props => [
        method,
        isFree,
        priceUnavailable,
        isCovered,
        overFreeAllowance,
        offersPaymentChoice,
        usesLegacySelector,
        creditsCost,
        creditsBalance,
        usdCost,
        arCost,
      ];
}
