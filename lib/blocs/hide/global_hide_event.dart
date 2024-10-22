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
