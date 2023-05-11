import 'package:equatable/equatable.dart';

abstract class ThemeSwitcherState extends Equatable {
  const ThemeSwitcherState();

  @override
  List<Object> get props => [];
}

class ThemeSwitcherInProgress extends ThemeSwitcherState {}

class ThemeSwitcherDarkTheme extends ThemeSwitcherState {}

class ThemeSwitcherLightTheme extends ThemeSwitcherState {}
