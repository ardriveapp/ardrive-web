import 'dart:async';

import 'package:arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drive/models/models.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

part 'profile_event.dart';
part 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final ProfileDao _profileDao;

  ProfileBloc({ProfileDao profileDao})
      : _profileDao = profileDao,
        super(ProfileUnavailable()) {
    add(ProfileCheckDefault());
  }

  @override
  Stream<ProfileState> mapEventToState(ProfileEvent event) async* {
    if (event is ProfileCheckDefault) {
      yield* _mapProfileCheckDefaultToState(event);
    } else if (event is ProfileLoad) {
      yield* _mapProfileLoadToState(event);
    } else if (event is Logout) yield* _mapLogoutToState(event);
  }

  Stream<ProfileState> _mapProfileCheckDefaultToState(
      ProfileCheckDefault event) async* {
    yield await _profileDao.hasProfile()
        ? ProfilePromptUnlock()
        : ProfilePromptAdd();
  }

  Stream<ProfileState> _mapProfileLoadToState(ProfileLoad event) async* {
    yield ProfileLoading();

    final profile = await _profileDao.loadDefaultProfile(event.password);

    if (profile != null) {
      yield ProfileLoaded(
        username: profile.details.username,
        password: event.password,
        wallet: profile.wallet,
        cipherKey: profile.key,
      );
    } else {
      yield ProfileUnavailable();
    }
  }

  Stream<ProfileState> _mapLogoutToState(Logout event) async* {
    yield ProfileUnavailable();

    add(ProfileCheckDefault());
  }
}
