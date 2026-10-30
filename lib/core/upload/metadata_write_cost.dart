import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/models/upload_review_summary.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/turbo.dart' show TurboBalanceRetriever;
import 'package:ardrive/utils/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';

/// The bytes [item] takes once an Arweave wallet signs it, the size Turbo
/// prices and counts against the free upload allowance. [item] need not be
/// signed yet.
int signedDataItemSize(DataItem item) => estimateDataItemSize(
      fileDataSize: item.data.lengthInBytes,
      // A data item keeps its tags base64url-encoded; this wants them as
      // written.
      tags: [
        for (final tag in item.tags)
          Tag(decodeBase64ToString(tag.name), decodeBase64ToString(tag.value)),
      ],
      nonce: decodeBase64ToBytes(item.nonce),
    );

/// The bytes of an ANS-104 bundle of items of [itemSizes]: what an AR
/// transaction carrying them weighs.
int bundleSize(List<int> itemSizes) =>
    32 + 64 * itemSizes.length + itemSizes.fold<int>(0, (a, b) => a + b);

/// What a metadata write costs, and who pays for it.
class MetadataWriteCost {
  const MetadataWriteCost(this.summary, {this.paidBy = const []});

  /// The cost, the way the upload review states it.
  final UploadReviewSummary summary;

  /// The wallets whose shared Turbo Credits are in the balance [summary]
  /// counted. The write names them to Turbo (`x-paid-by`), as an upload
  /// does, or Turbo charges the signer's own credits alone.
  final List<String> paidBy;

  /// The headers a write posted to Turbo sends.
  Map<String, String> get headers =>
      paidBy.isEmpty ? const {} : {'x-paid-by': paidBy.join(', ')};
}

/// What a metadata write costs: a license, a rename, a move. Small data
/// items, posted to Turbo one by one, or as one AR transaction when Turbo
/// uploads are off.
///
/// It answers with the upload review's own [UploadReviewSummary], decided by
/// the same rule, so a metadata write and an upload state their cost the same
/// way and the same review shows it: free when the free upload allowance
/// covers it, otherwise Turbo's price in Turbo Credits, and nothing goes
/// ahead that is neither free nor paid for.
///
/// One difference from the upload review, on purpose: an allowance that
/// could not be read is no price. An upload is priced in any case; a
/// metadata write is almost always free, so a price shown without knowing
/// would mostly be a wrong one.
class MetadataWriteCostReader {
  MetadataWriteCostReader({
    required PaymentService payments,
    required TurboUploadService turbo,
    required ArweaveService arweave,
  })  : _payments = payments,
        _turbo = turbo,
        _arweave = arweave,
        _balances = TurboBalanceRetriever(paymentService: payments);

  final PaymentService _payments;
  final TurboUploadService _turbo;
  final ArweaveService _arweave;
  final TurboBalanceRetriever _balances;

  /// Whether the write goes to Turbo. The wallet pays only when Turbo uploads
  /// are off: never as a fallback.
  bool get usesTurbo => _turbo.useTurboUpload;

  /// What writing items of [itemSizes] bytes costs [wallet], which holds
  /// [walletBalance] winston.
  ///
  /// [refusedByTurbo] is for after Turbo answered 402 to the write: whatever
  /// the allowance says, it is not free.
  Future<MetadataWriteCost> read({
    required List<int> itemSizes,
    required Wallet wallet,
    required BigInt walletBalance,
    bool refusedByTurbo = false,
  }) async =>
      usesTurbo
          ? await _readTurbo(itemSizes, wallet, refusedByTurbo)
          : MetadataWriteCost(await _readAr(itemSizes, walletBalance));

  Future<MetadataWriteCost> _readTurbo(
    List<int> itemSizes,
    Wallet wallet,
    bool refusedByTurbo,
  ) async {
    final total = itemSizes.fold<int>(0, (a, b) => a + b);

    // All three at once; none depends on another.
    final allowanceRead = _balances.getFreeAllowance(wallet);
    final balanceRead =
        _orNull(() => _balances.getBalanceAndPaidBy(wallet), 'balance');
    final priceRead = _orNull(() => _price(itemSizes), 'price');

    final allowance = await allowanceRead;
    final balanceAndPaidBy = await balanceRead;
    final balance = balanceAndPaidBy?.balance;
    final price = await priceRead;

    final freeStatus = freeUploadStatusFor(
      isSizeEligible: itemSizes.every((s) => s <= _turbo.maxFreeItemSizeBytes),
      byteCount: total,
      allowance: allowance,
      unknownIsFree: false,
    );

    final info = UploadPaymentMethodInfo(
      uploadMethod: UploadMethod.turbo,
      costEstimateTurbo: price ?? UploadCostEstimate.zero(),
      costEstimateAr: UploadCostEstimate.zero(),
      hasNoTurboBalance: balance == null || balance == BigInt.zero,
      isTurboUploadPossible: true,
      arBalance: '',
      // The wallet is not on offer while Turbo uploads are on.
      sufficientArBalance: false,
      turboCredits: '',
      sufficentCreditsBalance:
          price != null && balance != null && balance >= price.totalCost,
      freeStatus: freeStatus,
      totalSize: total,
      turboBalanceWinc: balance,
      turboUnreachable: price == null || balance == null || !allowance.isKnown,
    );

    return MetadataWriteCost(
      UploadReviewSummary.fromPaymentInfo(
        info,
        refusedByTurbo: refusedByTurbo,
      ),
      paidBy: balanceAndPaidBy?.paidBy ?? const [],
    );
  }

  /// Turbo's price for the items, with the US dollar figure when Turbo gives
  /// a rate. Turbo prices each item, so each is priced at the size of the
  /// largest: one request, at most a little over and never under.
  Future<UploadCostEstimate> _price(List<int> itemSizes) async {
    final largest = itemSizes.fold<int>(0, (a, b) => a > b ? a : b);
    final perItem = await _payments.getPriceForBytes(byteSize: largest);
    final winc = perItem * BigInt.from(itemSizes.length);
    double? usd;
    try {
      final perDollar = await _payments.getPriceForFiat(
          wallet: null, amount: 100, currency: 'usd');
      usd = winc / perDollar.winstonCredits;
    } catch (e) {
      // The cost shows in credits instead.
      logger.w('Could not get the Turbo Credits rate in US dollars: $e');
    }
    return UploadCostEstimate(
      pstFee: BigInt.zero,
      totalCost: winc,
      totalSize: itemSizes.fold<int>(0, (a, b) => a + b),
      usdUploadCost: usd,
    );
  }

  Future<UploadReviewSummary> _readAr(
    List<int> itemSizes,
    BigInt walletBalance,
  ) async {
    final size = bundleSize(itemSizes);
    final winston = await _orNull(
      () => _arweave.getPrice(byteSize: size),
      'AR price',
    );
    if (winston == null) return unavailable(method: UploadMethod.ar);

    return UploadReviewSummary.fromPaymentInfo(
      UploadPaymentMethodInfo(
        uploadMethod: UploadMethod.ar,
        costEstimateTurbo: null,
        costEstimateAr: UploadCostEstimate(
          pstFee: BigInt.zero,
          totalCost: winston,
          totalSize: size,
          usdUploadCost: null,
        ),
        hasNoTurboBalance: true,
        isTurboUploadPossible: false,
        arBalance: '',
        sufficientArBalance: walletBalance >= winston,
        turboCredits: '',
        sufficentCreditsBalance: false,
        freeStatus: FreeUploadStatus.notEligible,
        totalSize: size,
      ),
    );
  }

  /// No price: the review says so and offers to try again, and the write
  /// does not go ahead.
  static UploadReviewSummary unavailable({
    UploadMethod method = UploadMethod.turbo,
  }) =>
      UploadReviewSummary(
        method: method,
        isFree: false,
        priceUnavailable: true,
        isCovered: false,
        overFreeAllowance: false,
        offersPaymentChoice: false,
        usesLegacySelector: false,
        creditsCost: BigInt.zero,
        creditsBalance: BigInt.zero,
        usdCost: null,
        arCost: BigInt.zero,
      );

  Future<T?> _orNull<T>(Future<T> Function() read, String what) async {
    try {
      return await read();
    } catch (e) {
      logger.w('Could not read the $what for a metadata write: $e');
      return null;
    }
  }
}
