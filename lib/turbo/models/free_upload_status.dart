import 'package:ardrive/turbo/models/turbo_free_allowance.dart';

/// Whether an upload qualifies for Turbo's free tier, and if not, why not.
///
/// This is the single source of truth behind the free-tier message and the
/// payment method selector. It replaces a pair of booleans that could
/// contradict each other ("free" and "allowance used up" at the same time).
enum FreeUploadStatus {
  /// Small enough to qualify, and the wallet's allowance covers it.
  free,

  /// Would have been free on size, but the wallet's free allowance is known
  /// to be used up — so it needs Credits or AR after all. The remedy is more
  /// allowance or payment.
  allowanceUsedUp,

  /// Too large for the free tier (or Turbo is unavailable). The remedy is a
  /// smaller item, not more allowance.
  notEligible,
}

/// Derives the free-tier status for an upload of [byteCount] bytes.
///
/// [isSizeEligible] is the per-item size rule; [allowance] is the wallet's
/// remaining free pool. Both must pass for an upload to be free.
///
/// An unknown allowance yields [FreeUploadStatus.free] rather than
/// [FreeUploadStatus.allowanceUsedUp], because [TurboFreeAllowance.covers]
/// fails open: if we could not check, we fall back to the size-only behaviour
/// instead of telling a user with allowance left that they must pay.
FreeUploadStatus freeUploadStatusFor({
  required bool isSizeEligible,
  required int byteCount,
  required TurboFreeAllowance allowance,
}) {
  if (!isSizeEligible) return FreeUploadStatus.notEligible;
  if (allowance.isExhaustedFor(byteCount)) {
    return FreeUploadStatus.allowanceUsedUp;
  }

  return FreeUploadStatus.free;
}
