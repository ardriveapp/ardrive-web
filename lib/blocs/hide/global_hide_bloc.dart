import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'global_hide_event.dart';
part 'global_hide_state.dart';

class GlobalHideBloc extends Bloc<GlobalHideEvent, GlobalHideState> {
  final UserPreferencesRepository _userPreferencesRepository;
  final DriveDao _driveDao;

  GlobalHideBloc({
    required UserPreferencesRepository userPreferencesRepository,
    required DriveDao driveDao,
  })  : _userPreferencesRepository = userPreferencesRepository,
        _driveDao = driveDao,
        super(const GlobalHideInitial(userHasHiddenDrive: false)) {
    _userPreferencesRepository.watch().listen((userPreferences) async {
      if (isClosed) {
        return;
      }

      if (userPreferences.showHiddenFiles) {
        add(ShowItems(userHasHiddenItems: userPreferences.userHasHiddenDrive));
      } else {
        add(HideItems(userHasHiddenItems: userPreferences.userHasHiddenDrive));
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
      } else if (event is RefreshOptions) {
        final hasHiddenItems = await _driveDao.userHasHiddenItems();
        emit(state.copyWith(userHasHiddenDrive: hasHiddenItems));
      }
    });
  }
}
