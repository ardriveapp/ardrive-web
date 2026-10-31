part of 'global_hide_bloc.dart';

sealed class GlobalHideEvent extends Equatable {
  const GlobalHideEvent();

  @override
  List<Object> get props => [];
}

class HideItems extends GlobalHideEvent {
  final bool userHasHiddenItems;

  const HideItems({required this.userHasHiddenItems});
}

class ShowItems extends GlobalHideEvent {
  final bool userHasHiddenItems;

  const ShowItems({required this.userHasHiddenItems});
}

class RefreshOptions extends GlobalHideEvent {
  final bool userHasHiddenItems;

  const RefreshOptions({required this.userHasHiddenItems});
}

/// Event to sync local state with preferences stream without saving back.
/// This prevents infinite loops when the preferences stream emits updates.
class SyncShowHiddenState extends GlobalHideEvent {
  final bool showHidden;
  final bool userHasHiddenItems;

  const SyncShowHiddenState({
    required this.showHidden,
    required this.userHasHiddenItems,
  });

  @override
  List<Object> get props => [showHidden, userHasHiddenItems];
}
