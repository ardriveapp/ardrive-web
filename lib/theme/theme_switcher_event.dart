part of 'theme_switcher_bloc.dart';

abstract class ThemeSwitcherEvent extends Equatable {
  const ThemeSwitcherEvent();

  @override
  List<Object> get props => [];
}

class LoadTheme extends ThemeSwitcherEvent {}

class ChangeTheme extends ThemeSwitcherEvent {}
