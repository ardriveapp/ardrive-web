part of 'drive_create_cubit.dart';

@immutable
abstract class DriveCreateState extends Equatable {
  final DrivePrivacy privacy;

  const DriveCreateState({required this.privacy});

  DriveCreateState copyWith({DrivePrivacy? privacy}) {
    throw UnimplementedError();
  }

  @override
  List<Object> get props => [privacy];
}

class DriveCreateInitial extends DriveCreateState {
  const DriveCreateInitial({required super.privacy});

  @override
  DriveCreateInitial copyWith({DrivePrivacy? privacy}) {
    return DriveCreateInitial(privacy: privacy ?? this.privacy);
  }
}

class DriveCreateZeroBalance extends DriveCreateState {
  const DriveCreateZeroBalance({required super.privacy});

  @override
  DriveCreateZeroBalance copyWith({DrivePrivacy? privacy}) {
    return DriveCreateZeroBalance(privacy: privacy ?? this.privacy);
  }
}

class DriveCreateInProgress extends DriveCreateState {
  const DriveCreateInProgress({required super.privacy});

  @override
  DriveCreateInProgress copyWith({DrivePrivacy? privacy}) {
    return DriveCreateInProgress(privacy: privacy ?? this.privacy);
  }
}

class DriveCreateSuccess extends DriveCreateState {
  const DriveCreateSuccess({required super.privacy});

  @override
  DriveCreateSuccess copyWith({DrivePrivacy? privacy}) {
    return DriveCreateSuccess(privacy: privacy ?? this.privacy);
  }
}

class DriveCreateFailure extends DriveCreateState {
  final bool isPaymentError;

  /// The wallet can't make a private drive's key: its signature isn't the
  /// deterministic one a key must come from (a hardware wallet). Nothing was
  /// created or derived.
  final bool walletCantMakeDriveKeys;

  const DriveCreateFailure({
    required super.privacy,
    this.isPaymentError = false,
    this.walletCantMakeDriveKeys = false,
  });

  @override
  DriveCreateFailure copyWith({DrivePrivacy? privacy}) {
    return DriveCreateFailure(
      privacy: privacy ?? this.privacy,
      isPaymentError: isPaymentError,
      walletCantMakeDriveKeys: walletCantMakeDriveKeys,
    );
  }

  @override
  List<Object> get props => [privacy, isPaymentError, walletCantMakeDriveKeys];
}

class DriveCreateWalletMismatch extends DriveCreateState {
  const DriveCreateWalletMismatch({required super.privacy});

  @override
  DriveCreateWalletMismatch copyWith({DrivePrivacy? privacy}) {
    return DriveCreateWalletMismatch(privacy: privacy ?? this.privacy);
  }
}

/// The drive password typed didn't open any of the user's private drives
/// ([DriveUnlockFailure.wrongPassword]), or couldn't be checked. Nothing was
/// created.
class DriveCreateDrivePasswordRejected extends DriveCreateState {
  final DriveUnlockFailure reason;

  const DriveCreateDrivePasswordRejected({
    required super.privacy,
    required this.reason,
  });

  @override
  DriveCreateDrivePasswordRejected copyWith({DrivePrivacy? privacy}) =>
      DriveCreateDrivePasswordRejected(
          privacy: privacy ?? this.privacy, reason: reason);

  @override
  List<Object> get props => [privacy, reason];
}
