import 'dart:async';

import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive/turbo/models/turbo_free_allowance.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:arweave/arweave.dart' show Wallet;
import 'package:equatable/equatable.dart';
import 'package:pst/pst.dart';

/// What publishing an artifact would cost, and whether the user can pay it.
///
/// The modal's class doc says its job is "to make the confirm button an
/// informed click", and a permanent, irreversible purchase whose price is not
/// shown is not an informed click. This is the price.
class DriveStatePublishCost extends Equatable {
  /// Cost of a plain L1 transaction, in winston, including the PST fee.
  final UploadCostEstimate costEstimateAr;

  /// Cost of a bundled data item, in Turbo credits. [UploadCostEstimate.zero]
  /// when Turbo could not be asked — read [isTurboUploadPossible] first.
  final UploadCostEstimate costEstimateTurbo;

  /// Whether Turbo is a transport this user can choose at all: enabled in
  /// config, and its price actually quoted. False does not mean "too
  /// expensive" — that is [sufficientTurboBalance].
  final bool isTurboUploadPossible;

  final bool hasNoTurboBalance;

  /// Balances as the payment selector renders them.
  final String arBalance;
  final String turboCredits;

  final bool sufficientArBalance;
  final bool sufficientTurboBalance;

  /// Whether Turbo's free tier covers this artifact, and if not, why not.
  final FreeUploadStatus freeStatus;

  const DriveStatePublishCost({
    required this.costEstimateAr,
    required this.costEstimateTurbo,
    required this.isTurboUploadPossible,
    required this.hasNoTurboBalance,
    required this.arBalance,
    required this.turboCredits,
    required this.sufficientArBalance,
    required this.sufficientTurboBalance,
    required this.freeStatus,
  });

  bool get isFree => freeStatus == FreeUploadStatus.free;

  /// Whether [method] can actually pay for this artifact.
  ///
  /// The confirm button is enabled by this and nothing else. Mirrors
  /// `CreateSnapshotCubit._computeIsButtonEnabled`, including the rule that a
  /// free upload is payable whatever the balances say — Turbo bills it at
  /// zero, so there is nothing to be short of.
  bool canPayWith(UploadMethod method) {
    if (isFree) return true;

    return switch (method) {
      UploadMethod.ar => sufficientArBalance,
      UploadMethod.turbo => isTurboUploadPossible && sufficientTurboBalance,
    };
  }

  /// The method to open on.
  ///
  /// Turbo when it is available and would go through, because that is the
  /// cheaper transport and the one most users have credits for; AR otherwise,
  /// so a user with no credits is not shown a preselected method they cannot
  /// use. Either way the user can switch, and [canPayWith] governs the button.
  UploadMethod get defaultMethod =>
      canPayWith(UploadMethod.turbo) ? UploadMethod.turbo : UploadMethod.ar;

  /// Whether no method at all can pay for this artifact. The modal says so
  /// explicitly rather than leaving a disabled button unexplained.
  bool get isUnaffordable =>
      !canPayWith(UploadMethod.ar) && !canPayWith(UploadMethod.turbo);

  @override
  List<Object?> get props => [
        costEstimateAr,
        costEstimateTurbo,
        isTurboUploadPossible,
        hasNoTurboBalance,
        arBalance,
        turboCredits,
        sufficientArBalance,
        sufficientTurboBalance,
        freeStatus,
      ];
}

/// How long the AR leg may take before it is abandoned.
///
/// Longer than a Turbo leg because it is not one call: a price, a community
/// tip and an AR/USD conversion, each bounded in turn. It is also the leg that
/// must not fail, AR being the transport that always has to exist.
const kArCostLegTimeout = Duration(seconds: 20);

/// How long any single Turbo call may take before it is abandoned.
const kTurboLegTimeout = Duration(seconds: 6);

/// Worst case is 20 + 6 + 6 + 6 = 38 seconds, which stays under the cubit's
/// own 45-second deadline. That margin is what keeps the cubit's timeout a
/// backstop for something unforeseen rather than the thing that always fires
/// first, with nothing to say about which call is outstanding.

/// Prices an artifact with the same collaborators the snapshot dialog uses.
///
/// Deliberately not a second implementation: [UploadCostEstimateCalculatorForAR],
/// [TurboUploadCostCalculator] and [TurboBalanceRetriever] are the ones
/// `CreateSnapshotCubit` calls, wired the same way. A parallel pricing path
/// would be a second place for AR and Turbo costs to disagree, on a purchase
/// nobody can reverse.
class DriveStatePublishCostEstimator {
  final ArweaveService _arweave;
  final PaymentService _paymentService;
  final PstService _pst;
  final TurboBalanceRetriever _turboBalanceRetriever;
  final ConfigService _configService;

  /// Overrides every leg's own budget when set. Tests only.
  final Duration? _legTimeout;

  /// Overrides how long the community tip may take. Tests only, and separate
  /// from [_legTimeout] because the two have to be set independently: a test
  /// for the tip timing out needs the leg containing it to outlive it.
  final Duration? _pstFeeTimeout;

  DriveStatePublishCostEstimator({
    required ArweaveService arweave,
    required PaymentService paymentService,
    required PstService pst,
    required TurboBalanceRetriever turboBalanceRetriever,
    required ConfigService configService,
    Duration? legTimeout,
    Duration? pstFeeTimeout,
  })  : _arweave = arweave,
        _paymentService = paymentService,
        _pst = pst,
        _turboBalanceRetriever = turboBalanceRetriever,
        _configService = configService,
        _legTimeout = legTimeout,
        _pstFeeTimeout = pstFeeTimeout;

  /// Runs one leg of the estimate under its own deadline, and records how long
  /// it took.
  ///
  /// Two problems, one guard. None of the calls below has a timeout of its own,
  /// and several are guarded only against *errors* - a `try`/`catch` does
  /// nothing for a future that never completes. And the legs are awaited in
  /// sequence, so when one of them hangs the log says only that pricing began:
  /// it never names which call is outstanding.
  ///
  /// The per-leg deadline also keeps the total under the caller's own, so that
  /// one stays a backstop for something unforeseen rather than the thing that
  /// always fires first with nothing to say.
  Future<T> _leg<T>(
    String name,
    Duration budget,
    Future<T> Function() run,
  ) async {
    final deadline = _legTimeout ?? budget;
    final since = Stopwatch()..start();
    try {
      final value = await run().timeout(deadline);
      logger.d('[drive-state] priced $name in ${since.elapsedMilliseconds}ms');
      return value;
    } on TimeoutException {
      logger.e(
        '[drive-state] $name did not answer within ${deadline.inSeconds}s',
      );
      rethrow;
    }
  }

  /// Prices [sizeInBytes] against [wallet]'s balances.
  ///
  /// Throws if the AR price cannot be obtained. That is on purpose: AR is the
  /// transport that must always exist (§4.4), so failing to price it means
  /// there is no honest number to show, and the caller turns that into a
  /// refusal rather than a confirm button over a blank cost.
  Future<DriveStatePublishCost> estimate({
    required int sizeInBytes,
    required Wallet wallet,
    required BigInt walletBalance,
  }) async {
    final config = _configService.config;

    final arCalculator = UploadCostEstimateCalculatorForAR(
      arweaveService: _arweave,
      pstService: _pst,
      arCostToUsd: ConvertArToUSD(arweave: _arweave),
      // Only ever set by a test, which cannot afford to wait out the real one.
      pstFeeTimeout:
          _pstFeeTimeout ?? UploadCostEstimateCalculatorForAR.kPstFeeTimeout,
    );

    final turboCostCalculator = TurboCostCalculator(
      paymentService: _paymentService,
    );
    final turboCalculator = TurboUploadCostCalculator(
      turboCostCalculator: turboCostCalculator,
      priceEstimator: TurboPriceEstimator(
        wallet: wallet,
        paymentService: _paymentService,
        costCalculator: turboCostCalculator,
      ),
    );

    final costEstimateAr = await _leg(
      'the AR cost',
      kArCostLegTimeout,
      () => arCalculator.calculateCost(totalSize: sizeInBytes),
    );

    // Turbo failing to quote is not fatal — AR still is a transport — so it
    // degrades to "Turbo is not on offer" rather than to a failed publish.
    var isTurboUploadPossible = config.useTurboUpload;
    var costEstimateTurbo = UploadCostEstimate.zero();
    if (isTurboUploadPossible) {
      try {
        costEstimateTurbo = await _leg(
          'the Turbo cost',
          kTurboLegTimeout,
          () => turboCalculator.calculateCost(totalSize: sizeInBytes),
        );
      } catch (e) {
        logger.w(
          '[drive-state] Turbo could not price the artifact; AR remains '
          'available: $e',
        );
        isTurboUploadPossible = false;
      }
    }

    // `try`/`catch` rather than `.catchError`, to match the guard above and
    // because the two are not equivalent: `.catchError` is attached to a future
    // the call has already returned, so a collaborator that throws on the way
    // to returning one is not caught by it at all.
    BigInt turboBalance;
    try {
      turboBalance = await _leg(
        'the Turbo balance',
        kTurboLegTimeout,
        () => _turboBalanceRetriever.getBalance(wallet),
      );
    } catch (e) {
      logger.e('[drive-state] could not read the Turbo balance', e);
      turboBalance = BigInt.zero;
    }

    return DriveStatePublishCost(
      costEstimateAr: costEstimateAr,
      costEstimateTurbo: costEstimateTurbo,
      isTurboUploadPossible: isTurboUploadPossible,
      hasNoTurboBalance: turboBalance == BigInt.zero,
      arBalance: convertWinstonToLiteralString(walletBalance),
      turboCredits: convertWinstonToLiteralString(turboBalance),
      sufficientArBalance: walletBalance >= costEstimateAr.totalCost,
      sufficientTurboBalance: costEstimateTurbo.totalCost <= turboBalance,
      freeStatus: await _freeStatus(
        sizeInBytes: sizeInBytes,
        wallet: wallet,
        isTurboUploadPossible: isTurboUploadPossible,
      ),
    );
  }

  /// Being small enough is not sufficient: the wallet's free allowance has to
  /// cover it too, or Turbo rejects the upload with a 402 after the user was
  /// told it was free.
  ///
  /// Asking costs a request to the payment service, and that request failing is
  /// a Turbo failure like any other: it degrades to "not free", never to a
  /// failed estimate. An estimate that throws is an artifact that is never
  /// offered at all — so letting this one line escape would mean a Turbo outage
  /// silently removing the feature from users who were going to pay in AR.
  Future<FreeUploadStatus> _freeStatus({
    required int sizeInBytes,
    required Wallet wallet,
    required bool isTurboUploadPossible,
  }) async {
    if (!isTurboUploadPossible) return FreeUploadStatus.notEligible;

    final isSizeEligible =
        sizeInBytes <= _configService.config.allowedDataItemSizeForTurbo;
    if (!isSizeEligible) return FreeUploadStatus.notEligible;

    final TurboFreeAllowance allowance;
    try {
      allowance = await _leg(
        'the Turbo free allowance',
        kTurboLegTimeout,
        () => _turboBalanceRetriever.getFreeAllowance(wallet),
      );
    } catch (e) {
      logger.w(
        '[drive-state] Turbo could not report a free allowance; the artifact '
        'is priced as a paid upload: $e',
      );
      return FreeUploadStatus.notEligible;
    }

    return freeUploadStatusFor(
      isSizeEligible: true,
      byteCount: sizeInBytes,
      allowance: allowance,
    );
  }
}
