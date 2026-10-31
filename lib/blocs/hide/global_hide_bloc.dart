import 'dart:async';

import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'global_hide_event.dart';
part 'global_hide_state.dart';

class GlobalHideBloc extends Bloc<GlobalHideEvent, GlobalHideState> {
  final UserPreferencesRepository _userPreferencesRepository;
  final DriveDao _driveDao;
  StreamSubscription<UserPreferences>? _prefsSubscription;

  GlobalHideBloc({
    required UserPreferencesRepository userPreferencesRepository,
    required DriveDao driveDao,
  })  : _userPreferencesRepository = userPreferencesRepository,
        _driveDao = driveDao,
        super(const GlobalHideInitial(userHasHiddenDrive: false)) {
    // Listen to preferences stream to update state when preferences change.
    // Note: We only update local state here, NOT save back to preferences.
    // Saving is done only in response to user actions (ToggleShowHiddenFiles).
    _prefsSubscription =
        _userPreferencesRepository.watch().listen((userPreferences) async {
      if (userPreferences.showHiddenFiles) {
        add(SyncShowHiddenState(
          showHidden: true,
          userHasHiddenItems: userPreferences.userHasHiddenDrive,
        ));
      } else {
        add(SyncShowHiddenState(
          showHidden: false,
          userHasHiddenItems: userPreferences.userHasHiddenDrive,
        ));
      }
    });

    _userPreferencesRepository.load();

    on<GlobalHideEvent>((event, emit) async {
      if (event is ShowItems) {
        emit(ShowingHiddenItems(userHasHiddenDrive: event.userHasHiddenItems));
        await _userPreferencesRepository.saveShowHiddenFiles(true);
      } else if (event is HideItems) {
        emit(HiddingItems(userHasHiddenDrive: event.userHasHiddenItems));
        await _userPreferencesRepository.saveShowHiddenFiles(false);
      } else if (event is SyncShowHiddenState) {
        // Only update local state from stream updates, don't save back
        if (event.showHidden) {
          emit(ShowingHiddenItems(userHasHiddenDrive: event.userHasHiddenItems));
        } else {
          emit(HiddingItems(userHasHiddenDrive: event.userHasHiddenItems));
        }
      } else if (event is RefreshOptions) {
        final hasHiddenItems = await _driveDao.userHasHiddenItems();
        emit(state.copyWith(userHasHiddenDrive: hasHiddenItems));
      }
    });
  }

  @override
  Future<void> close() async {
    await _prefsSubscription?.cancel();
    return super.close();
  }
}
