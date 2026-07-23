import 'package:ardrive/turbo/models/turbo_free_allowance.dart';

/// Whether an upload qualifies for Turbo's free tier, and if not, why not.
///
/// This is the single source of truth behind the free-tier message and the
/// payment method selector. It replaces a pair of booleans that could
/// contradict each other ("free" and "allowance used up" at the same time).
enum FreeUploadStatus {
  /// Small enough to qualify, and the wallet's allowance covers it.
  free,

  /// Size-eligible, and the wallet still has some free allowance, but this
  /// upload is larger than what is left — so it needs Credits or AR. Distinct
  /// from [allowanceUsedUp]: the user has NOT exhausted their free tier, the
  /// upload simply exceeds it. We deliberately do not predict how much of the
  /// upload ends up free (see [freeUploadStatusFor]).
  exceedsAllowance,

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
/// When the upload is size-eligible but the allowance does not cover it, the
/// result distinguishes [FreeUploadStatus.exceedsAllowance] (some allowance
/// remains, the upload is just bigger) from [FreeUploadStatus.allowanceUsedUp]
/// (the free tier is gone). It deliberately does NOT try to say how many bytes
/// end up free: the client cannot know that. Turbo applies the free tier
/// server-side, its billing granularity (per-item vs per-bundle) is not
/// exposed, and a second per-IP pool that `/v1/account/free` does not report
/// can constrain it further. So [byteCount] vs the wallet allowance only tells
/// us the upload exceeds what is free — never the exact split. The 402 on
/// upload remains the authority on what is actually charged.
///
/// An unknown allowance yields [FreeUploadStatus.free] rather than a paid
/// status, because [TurboFreeAllowance.covers] fails open: if we could not
/// check, we fall back to the size-only behaviour instead of telling a user
/// with allowance left that they must pay.
FreeUploadStatus freeUploadStatusFor({
  required bool isSizeEligible,
  required int byteCount,
  required TurboFreeAllowance allowance,
}) {
  if (!isSizeEligible) return FreeUploadStatus.notEligible;
  if (!allowance.isExhaustedFor(byteCount)) return FreeUploadStatus.free;

  // Known not to cover the upload. If a positive allowance remains, the upload
  // exceeds it rather than the free tier being spent.
  return allowance.bytesRemaining > 0
      ? FreeUploadStatus.exceedsAllowance
      : FreeUploadStatus.allowanceUsedUp;
}
