import 'package:equatable/equatable.dart';

/// How much of the wallet's Turbo free-upload allowance is left.
enum TurboFreeAllowanceStatus {
  /// The wallet is exempt from the free-tier cap (partner/exempt wallet).
  unlimited,

  /// The wallet has a finite, non-zero number of free bytes left.
  limited,

  /// The free tier is off for this wallet, or its pool is fully used up.
  disabled,

  /// We could not determine the allowance (endpoint unavailable, unexpected
  /// payload, wallet unknown to the payment service, ...).
  unknown,
}

/// The wallet's remaining Turbo free-upload allowance, from
/// `GET /v1/account/free?address=<wallet>`.
///
/// This value is **advisory only**. It is a point-in-time, wallet-level
/// snapshot that races with uploads from other tabs, devices and in-flight
/// bundles. Use it to decide what to *promise* the user before an upload —
/// never to gate one. The authority on whether an upload is actually free
/// remains Turbo's response to the upload itself: a 402 means it was not.
///
/// See also [TurboFreeAllowance.covers], which deliberately fails open.
class TurboFreeAllowance extends Equatable {
  final TurboFreeAllowanceStatus status;

  /// Bytes left in the free pool. Only meaningful when [status] is
  /// [TurboFreeAllowanceStatus.limited]; zero otherwise.
  final int bytesRemaining;

  const TurboFreeAllowance._(this.status, this.bytesRemaining);

  const TurboFreeAllowance.unlimited()
      : this._(TurboFreeAllowanceStatus.unlimited, 0);

  const TurboFreeAllowance.disabled()
      : this._(TurboFreeAllowanceStatus.disabled, 0);

  const TurboFreeAllowance.unknown()
      : this._(TurboFreeAllowanceStatus.unknown, 0);

  /// A finite allowance. A non-positive [bytesRemaining] is normalised to
  /// [TurboFreeAllowance.disabled] so callers never have to special-case zero.
  factory TurboFreeAllowance.bytes(int bytesRemaining) => bytesRemaining <= 0
      ? const TurboFreeAllowance.disabled()
      : TurboFreeAllowance._(TurboFreeAllowanceStatus.limited, bytesRemaining);

  /// Parses the `/v1/account/free` payload: `{ "bytesRemaining": 7340032 }`,
  /// where a null `bytesRemaining` means unlimited and `0` means the free tier
  /// is off. Anything unrecognised is [TurboFreeAllowance.unknown] rather than
  /// an exception — an advisory value must never break upload preparation.
  factory TurboFreeAllowance.fromJson(dynamic data) {
    if (data is! Map || !data.containsKey('bytesRemaining')) {
      return const TurboFreeAllowance.unknown();
    }

    final value = data['bytesRemaining'];

    // Explicit null is the documented "unlimited" signal, not a missing field.
    if (value == null) return const TurboFreeAllowance.unlimited();
    if (value is num) return TurboFreeAllowance.bytes(value.toInt());

    return const TurboFreeAllowance.unknown();
  }

  bool get isKnown => status != TurboFreeAllowanceStatus.unknown;

  /// Whether the pool can cover [byteCount] of free-eligible upload.
  ///
  /// An [TurboFreeAllowanceStatus.unknown] allowance answers `true`: when the
  /// endpoint is unreachable we fall back to promising free on item size
  /// alone, exactly as the app behaved before this endpoint existed. Failing
  /// closed would tell users with allowance left that they must pay, which is
  /// a worse and less recoverable error than the 402 we already handle.
  bool covers(int byteCount) {
    switch (status) {
      case TurboFreeAllowanceStatus.unlimited:
      case TurboFreeAllowanceStatus.unknown:
        return true;
      case TurboFreeAllowanceStatus.disabled:
        return false;
      case TurboFreeAllowanceStatus.limited:
        return byteCount <= bytesRemaining;
    }
  }

  /// True only when we *know* the pool cannot cover [byteCount] — i.e. the
  /// allowance is genuinely used up, as opposed to merely unknown. This is the
  /// signal for telling the user their free allowance ran out; [covers] alone
  /// cannot distinguish "used up" from "could not check".
  bool isExhaustedFor(int byteCount) => isKnown && !covers(byteCount);

  @override
  List<Object?> get props => [status, bytesRemaining];

  @override
  String toString() =>
      'TurboFreeAllowance{status: $status, bytesRemaining: $bytesRemaining}';
}
