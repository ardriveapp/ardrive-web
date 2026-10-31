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
  StreamSubscription<bool>? _hiddenItemsSubscription;

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
      // Only whether to show them comes from the preferences. Whether there
      // is anything hidden is the database's to say (below): the stored
      // flag counted hidden drives alone and lagged a sync, so the eye came
      // and went at the wrong times.
      add(SyncShowHiddenState(
        showHidden: userPreferences.showHiddenFiles,
        userHasHiddenItems: state.userHasHiddenDrive,
      ));
    });

    // Hidden drives, folders and files, as the database has them now, so the
    // toggle is offered exactly while there is something for it to show.
    _hiddenItemsSubscription = _driveDao.watchUserHasHiddenItems().listen(
          (hasHidden) => add(HiddenItemsChanged(userHasHiddenItems: hasHidden)),
        );

    _userPreferencesRepository.load();

    on<GlobalHideEvent>((event, emit) async {
      if (event is ShowItems) {
        emit(ShowingHiddenItems(userHasHiddenDrive: event.userHasHiddenItems));
        await _userPreferencesRepository.saveShowHiddenFiles(true);
      } else if (event is HideItems) {
        emit(HiddingItems(userHasHiddenDrive: event.userHasHiddenItems));
        await _userPreferencesRepository.saveShowHiddenFiles(false);
      } else if (event is SyncShowHiddenState) {
        // Only update local state from stream updates, don't save back.
        // Whether anything is hidden is read when the event is handled, not
        // when it was added, so a database answer handled in between stands.
        if (event.showHidden) {
          emit(
              ShowingHiddenItems(userHasHiddenDrive: state.userHasHiddenDrive));
        } else {
          emit(HiddingItems(userHasHiddenDrive: state.userHasHiddenDrive));
        }
      } else if (event is HiddenItemsChanged) {
        if (event.userHasHiddenItems != state.userHasHiddenDrive) {
          emit(state.copyWith(userHasHiddenDrive: event.userHasHiddenItems));
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
    await _hiddenItemsSubscription?.cancel();
    return super.close();
  }
}
