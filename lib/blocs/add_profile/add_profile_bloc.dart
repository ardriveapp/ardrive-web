import 'dart:async';
import 'dart:convert';

import 'package:arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:drive/blocs/blocs.dart';
import 'package:drive/models/models.dart';
import 'package:meta/meta.dart';

part 'add_profile_event.dart';
part 'add_profile_state.dart';

class AddProfileBloc extends Bloc<AddProfileEvent, AddProfileState> {
  final ProfileBloc _profileBloc;
  final ProfileDao _profileDao;

  AddProfileBloc(
      {@required ProfileBloc profileBloc, @required ProfileDao profileDao})
      : _profileBloc = profileBloc,
        _profileDao = profileDao,
        super(AddProfileInitial());

  @override
  Stream<AddProfileState> mapEventToState(
    AddProfileEvent event,
  ) async* {
    if (event is AddProfileAttempted) {
      yield* _mapAddProfileAttemptedToState(event);
    }
  }

  Stream<AddProfileState> _mapAddProfileAttemptedToState(
      AddProfileAttempted event) async* {
    yield AddProfileInProgress();

    final wallet = Wallet.fromJwk(json.decode(event.walletJson));

    await _profileDao.addProfile(event.username, event.password, wallet);

    yield AddProfileSuccessful();

    _profileBloc.add(ProfileLoad(event.password));
  }
}
