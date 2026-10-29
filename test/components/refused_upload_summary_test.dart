import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/components/upload_form.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The review after Turbo refused an upload, read again by Try again.
void main() {
  UploadCostEstimate cost(int winc) => UploadCostEstimate(
        pstFee: BigInt.zero,
        totalCost: BigInt.from(winc),
        totalSize: 1,
        usdUploadCost: 1,
      );

  /// A free upload that went ahead while Turbo's price couldn't be read.
  final reviewed = UploadPaymentMethodInfo(
    uploadMethod: UploadMethod.turbo,
    costEstimateTurbo: UploadCostEstimate.zero(),
    costEstimateAr: cost(100),
    hasNoTurboBalance: true,
    isTurboUploadPossible: true,
    arBalance: '0',
    sufficientArBalance: false,
    turboCredits: '0',
    sufficentCreditsBalance: false,
    freeStatus: FreeUploadStatus.free,
    totalSize: 4096,
    turboUnreachable: true,
  );

  test('a price unread at review is read again, so Try again can recover',
      () async {
    final asked = <int>[];
    final s = await readRefusedUploadSummary(
      reviewed,
      readBalance: () async => BigInt.from(9000),
      readPrice: (bytes) async {
        asked.add(bytes);
        return cost(5875);
      },
    );

    expect(asked, [4096]);
    expect(s.priceUnavailable, isFalse);
    expect(s.creditsCost, BigInt.from(5875));
    expect(s.isCovered, isTrue);
  });

  test('while Turbo still does not answer, it is still no price', () async {
    final s = await readRefusedUploadSummary(
      reviewed,
      readBalance: () async => BigInt.from(9000),
      readPrice: (_) async => throw Exception('unreachable'),
    );

    expect(s.priceUnavailable, isTrue);
  });

  test('a price read at review is kept, not asked again', () async {
    var asked = false;
    final s = await readRefusedUploadSummary(
      reviewed.copyWith(costEstimateTurbo: cost(5875)),
      readBalance: () async => BigInt.zero,
      readPrice: (_) async {
        asked = true;
        return cost(1);
      },
    );

    expect(asked, isFalse);
    expect(s.needsCredits, isTrue);
  });

  test('a wallet Turbo has never seen has no credits', () async {
    final s = await readRefusedUploadSummary(
      reviewed.copyWith(costEstimateTurbo: cost(5875)),
      readBalance: () async => throw TurboUserNotFound(),
      readPrice: (_) async => cost(5875),
    );

    expect(s.priceUnavailable, isFalse);
    expect(s.creditsBalance, BigInt.zero);
  });

  test('a balance that can not be read is no price, and Try again', () async {
    final s = await readRefusedUploadSummary(
      reviewed.copyWith(costEstimateTurbo: cost(5875)),
      readBalance: () async => throw Exception('down'),
      readPrice: (_) async => cost(5875),
    );

    expect(s.priceUnavailable, isTrue);
  });
}
