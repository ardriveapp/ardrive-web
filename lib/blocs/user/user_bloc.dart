import 'dart:async';

import 'package:arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';

part 'user_event.dart';
part 'user_state.dart';

class UserBloc extends Bloc<UserEvent, UserState> {
  UserBloc() : super(UserAuthenticated());

  @override
  Stream<UserState> mapEventToState(
    UserEvent event,
  ) async* {
    if (event is AttemptLogin)
      yield* _mapAttemptLoginToState(event);
    else if (event is Logout) yield* _mapLogoutToState(event);
  }

  Stream<UserState> _mapAttemptLoginToState(AttemptLogin event) async* {
    yield UserAuthenticating();

    final wallet = Wallet.fromJwk(event.jwk);

    yield UserAuthenticated(userWallet: wallet);
  }

  Stream<UserState> _mapLogoutToState(Logout event) async* {
    yield UserUnauthenticated();
  }
}
