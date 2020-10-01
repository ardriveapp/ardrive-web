import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:drive/blocs/blocs.dart';
import 'package:drive/models/models.dart';
import 'package:meta/meta.dart';

part 'unlock_profile_event.dart';
part 'unlock_profile_state.dart';

class UnlockProfileBloc extends Bloc<UnlockProfileEvent, UnlockProfileState> {
  final ProfileBloc _profileBloc;
  final ProfileDao _profileDao;

  UnlockProfileBloc(
      {@required ProfileBloc profileBloc, @required ProfileDao profileDao})
      : _profileBloc = profileBloc,
        _profileDao = profileDao,
        super(UnlockProfileInitial());

  @override
  Stream<UnlockProfileState> mapEventToState(
    UnlockProfileEvent event,
  ) async* {
    // TODO: implement mapEventToState
  }
}
