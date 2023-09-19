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
  const DriveCreateFailure({required super.privacy});

  @override
  DriveCreateFailure copyWith({DrivePrivacy? privacy}) {
    return DriveCreateFailure(privacy: privacy ?? this.privacy);
  }
}

class DriveCreateWalletMismatch extends DriveCreateState {
  const DriveCreateWalletMismatch({required super.privacy});

  @override
  DriveCreateWalletMismatch copyWith({DrivePrivacy? privacy}) {
    return DriveCreateWalletMismatch(privacy: privacy ?? this.privacy);
  }
}
