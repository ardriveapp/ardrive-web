import 'dart:async';

import 'package:arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';

part 'profile_event.dart';
part 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  ProfileBloc() : super(ProfileInactive());

  @override
  Stream<ProfileState> mapEventToState(
    ProfileEvent event,
  ) async* {
    if (event is AttemptLogin) {
      yield* _mapAttemptLoginToState(event);
    } else if (event is Logout) yield* _mapLogoutToState(event);
  }

  Stream<ProfileState> _mapAttemptLoginToState(AttemptLogin event) async* {
    yield UserAuthenticating();

    final wallet = Wallet.fromJwk(event.jwk);

    yield ProfileActive(userWallet: wallet);
  }

  Stream<ProfileState> _mapLogoutToState(Logout event) async* {
    yield ProfileInactive();
  }
}
