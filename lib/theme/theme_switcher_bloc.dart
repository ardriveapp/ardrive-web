import 'package:ardrive/theme/theme_switcher_state.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'theme_switcher_event.dart';

class ThemeSwitcherBloc extends Bloc<ThemeSwitcherEvent, ThemeSwitcherState> {
  final UserPreferencesRepository _userPreferencesRepository;

  ThemeSwitcherBloc({
    required UserPreferencesRepository userPreferencesRepository,
  })  : _userPreferencesRepository = userPreferencesRepository,
        super(ThemeSwitcherInProgress()) {
    on<ThemeSwitcherEvent>((event, emit) async {
      if (event is LoadTheme) {
        _loadTheme(emit);
      } else if (event is ChangeTheme) {
        _changeTheme(emit);
      }
    });
  }

  void _loadTheme(Emitter<ThemeSwitcherState> emit) async {
    emit(ThemeSwitcherInProgress());

    final theme = (await _userPreferencesRepository.load()).currentTheme;

    if (theme == ArDriveThemes.light) {
      emit(ThemeSwitcherLightTheme());
    } else {
      emit(ThemeSwitcherDarkTheme());
    }
  }

  void _changeTheme(Emitter<ThemeSwitcherState> emit) async {
    if (state is ThemeSwitcherLightTheme) {
      emit(ThemeSwitcherDarkTheme());
      await _userPreferencesRepository.saveTheme(ArDriveThemes.dark);
    } else if (state is ThemeSwitcherDarkTheme) {
      emit(ThemeSwitcherLightTheme());
      await _userPreferencesRepository.saveTheme(ArDriveThemes.light);
    }
  }
}
