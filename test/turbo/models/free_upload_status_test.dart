import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive/turbo/models/turbo_free_allowance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('freeUploadStatusFor', () {
    test('is notEligible when an item is too large, regardless of allowance',
        () {
      expect(
        freeUploadStatusFor(
          isSizeEligible: false,
          byteCount: 10,
          allowance: const TurboFreeAllowance.unlimited(),
        ),
        FreeUploadStatus.notEligible,
      );
    });

    test('is free when the allowance covers the upload', () {
      expect(
        freeUploadStatusFor(
          isSizeEligible: true,
          byteCount: 100,
          allowance: TurboFreeAllowance.bytes(200),
        ),
        FreeUploadStatus.free,
      );
    });

    test('is free at the exact boundary where allowance equals the upload', () {
      expect(
        freeUploadStatusFor(
          isSizeEligible: true,
          byteCount: 200,
          allowance: TurboFreeAllowance.bytes(200),
        ),
        FreeUploadStatus.free,
      );
    });

    test('is free for an unlimited allowance', () {
      expect(
        freeUploadStatusFor(
          isSizeEligible: true,
          byteCount: 1 << 30,
          allowance: const TurboFreeAllowance.unlimited(),
        ),
        FreeUploadStatus.free,
      );
    });

    test(
        'exceedsAllowance when some allowance remains but the upload is bigger',
        () {
      expect(
        freeUploadStatusFor(
          isSizeEligible: true,
          byteCount: 201,
          allowance: TurboFreeAllowance.bytes(200),
        ),
        FreeUploadStatus.exceedsAllowance,
      );
    });

    test('exceedsAllowance even one byte over the remaining allowance', () {
      expect(
        freeUploadStatusFor(
          isSizeEligible: true,
          byteCount: 2,
          allowance: TurboFreeAllowance.bytes(1),
        ),
        FreeUploadStatus.exceedsAllowance,
      );
    });

    test('is allowanceUsedUp when the free tier is off (zero remaining)', () {
      expect(
        freeUploadStatusFor(
          isSizeEligible: true,
          byteCount: 100,
          allowance: const TurboFreeAllowance.disabled(),
        ),
        FreeUploadStatus.allowanceUsedUp,
      );
    });

    test(
        'falls open to free when the allowance is unknown, so an unreachable '
        'endpoint never forces payment', () {
      expect(
        freeUploadStatusFor(
          isSizeEligible: true,
          byteCount: 1 << 30,
          allowance: const TurboFreeAllowance.unknown(),
        ),
        FreeUploadStatus.free,
      );
    });

    test(
        'item-size ineligibility wins over an exhausted allowance: the remedy '
        'is a smaller item, not payment framing about the pool', () {
      expect(
        freeUploadStatusFor(
          isSizeEligible: false,
          byteCount: 100,
          allowance: const TurboFreeAllowance.disabled(),
        ),
        FreeUploadStatus.notEligible,
      );
    });
  });
}
