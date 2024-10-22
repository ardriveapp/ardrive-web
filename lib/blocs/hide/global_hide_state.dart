part of 'global_hide_bloc.dart';

sealed class GlobalHideState extends Equatable {
  const GlobalHideState({
    required this.userHasHiddenDrive,
  });

  final bool userHasHiddenDrive;

  @override
  List<Object> get props => [userHasHiddenDrive];

  GlobalHideState copyWith({
    bool? userHasHiddenDrive,
  });
}

final class GlobalHideInitial extends GlobalHideState {
  const GlobalHideInitial({
    required super.userHasHiddenDrive,
  });

  @override
  GlobalHideState copyWith({
    bool? userHasHiddenDrive,
  }) {
    return GlobalHideInitial(
      userHasHiddenDrive: userHasHiddenDrive ?? this.userHasHiddenDrive,
    );
  }
}

final class ShowingHiddenItems extends GlobalHideState {
  const ShowingHiddenItems({
    required super.userHasHiddenDrive,
  });

  @override
  GlobalHideState copyWith({
    bool? userHasHiddenDrive,
  }) {
    return ShowingHiddenItems(
      userHasHiddenDrive: userHasHiddenDrive ?? this.userHasHiddenDrive,
    );
  }
}

final class HiddingItems extends GlobalHideState {
  const HiddingItems({
    required super.userHasHiddenDrive,
  });

  @override
  GlobalHideState copyWith({
    bool? userHasHiddenDrive,
  }) {
    return HiddingItems(
      userHasHiddenDrive: userHasHiddenDrive ?? this.userHasHiddenDrive,
    );
  }
}
