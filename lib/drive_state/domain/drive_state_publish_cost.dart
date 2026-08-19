import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
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

  DriveStatePublishCostEstimator({
    required ArweaveService arweave,
    required PaymentService paymentService,
    required PstService pst,
    required TurboBalanceRetriever turboBalanceRetriever,
    required ConfigService configService,
  })  : _arweave = arweave,
        _paymentService = paymentService,
        _pst = pst,
        _turboBalanceRetriever = turboBalanceRetriever,
        _configService = configService;

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

    final costEstimateAr =
        await arCalculator.calculateCost(totalSize: sizeInBytes);

    // Turbo failing to quote is not fatal — AR still is a transport — so it
    // degrades to "Turbo is not on offer" rather than to a failed publish.
    var isTurboUploadPossible = config.useTurboUpload;
    var costEstimateTurbo = UploadCostEstimate.zero();
    if (isTurboUploadPossible) {
      try {
        costEstimateTurbo =
            await turboCalculator.calculateCost(totalSize: sizeInBytes);
      } catch (e) {
        logger.w(
          '[drive-state] Turbo could not price the artifact; AR remains '
          'available: $e',
        );
        isTurboUploadPossible = false;
      }
    }

    final turboBalance =
        await _turboBalanceRetriever.getBalance(wallet).catchError((Object e) {
      logger.e('[drive-state] could not read the Turbo balance', e);
      return BigInt.zero;
    });

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
  Future<FreeUploadStatus> _freeStatus({
    required int sizeInBytes,
    required Wallet wallet,
    required bool isTurboUploadPossible,
  }) async {
    if (!isTurboUploadPossible) return FreeUploadStatus.notEligible;

    final isSizeEligible =
        sizeInBytes <= _configService.config.allowedDataItemSizeForTurbo;
    if (!isSizeEligible) return FreeUploadStatus.notEligible;

    return freeUploadStatusFor(
      isSizeEligible: true,
      byteCount: sizeInBytes,
      allowance: await _turboBalanceRetriever.getFreeAllowance(wallet),
    );
  }
}
