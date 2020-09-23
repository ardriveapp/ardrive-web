import 'dart:async';

import 'package:arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:drive/entities/crypto/cipher_key.dart';
import 'package:drive/models/models.dart';
import 'package:meta/meta.dart';

part 'profile_event.dart';
part 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final ProfileDao _profileDao;

  ProfileBloc({ProfileDao profileDao})
      : _profileDao = profileDao,
        super(ProfileInactive());

  @override
  Stream<ProfileState> mapEventToState(
    ProfileEvent event,
  ) async* {
    if (event is ProfileAdd) {
      yield* _mapProfileAddToState(event);
    } else if (event is Logout) yield* _mapLogoutToState(event);
  }

  Stream<ProfileState> _mapProfileAddToState(ProfileAdd event) async* {
    yield ProfileActivating();

    final wallet = Wallet.fromJwk(event.jwk);

    final profileKey =
        await _profileDao.addProfile(event.username, event.password, wallet);

    yield ProfileActive(
      username: event.username,
      password: event.password,
      wallet: wallet,
      cipherKey: profileKey,
    );
  }

  Stream<ProfileState> _mapLogoutToState(Logout event) async* {
    yield ProfileInactive();
  }
}
