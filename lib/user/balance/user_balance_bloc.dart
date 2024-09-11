import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/user/user.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'user_balance_event.dart';
part 'user_balance_state.dart';

class UserBalanceBloc extends Bloc<UserBalanceEvent, UserBalanceState> {
  final ArDriveAuth _auth;
  StreamSubscription<User?>? _userSubscription;

  UserBalanceBloc({required ArDriveAuth auth})
      : _auth = auth,
        super(UserBalanceInitial()) {
    on<GetUserBalance>(_onGetUserBalance);
    on<RefreshUserBalance>(_onRefreshUserBalance);
  }

  Future<void> _onGetUserBalance(
      GetUserBalance event, Emitter<UserBalanceState> emit) async {
    await _cancelSubscription();

    final user = _auth.currentUser;
    _emitUserBalanceState(user, emit);

    _userSubscription = _auth.onAuthStateChanged().listen((user) {
      if (isClosed) return;
      _emitUserBalanceState(user, emit);
      if (user?.ioTokens != null) {
        _cancelSubscription();
      }
    });

    await _userSubscription?.asFuture();
  }

  Future<void> _onRefreshUserBalance(
      RefreshUserBalance event, Emitter<UserBalanceState> emit) async {
    if (isClosed) return;

    await _cancelSubscription();

    emit(UserBalanceLoadingIOTokens(
      arBalance: _auth.currentUser.walletBalance,
      errorFetchingIOTokens: false,
    ));

    _auth.refreshBalance();

    _userSubscription = _auth.onAuthStateChanged().listen((user) {
      if (isClosed) return;
      _emitUserBalanceState(user, emit);
      if (user?.ioTokens != null) {
        _cancelSubscription();
      }
    });

    await _userSubscription?.asFuture();
  }

  Future<void> _cancelSubscription() async {
    if (_userSubscription != null) {
      await _userSubscription!.cancel();
      _userSubscription = null;
    }
  }

  void _emitUserBalanceState(User? user, Emitter<UserBalanceState> emit) {
    if (user == null) return;

    if (user.ioTokens == null && !user.errorFetchingIOTokens) {
      emit(UserBalanceLoadingIOTokens(
        arBalance: user.walletBalance,
        errorFetchingIOTokens: user.errorFetchingIOTokens,
      ));
    } else {
      emit(UserBalanceLoaded(
        arBalance: user.walletBalance,
        ioTokens: user.ioTokens,
        errorFetchingIOTokens: user.errorFetchingIOTokens,
      ));
    }
  }

  @override
  Future<void> close() async {
    await _cancelSubscription();
    return super.close();
  }
}
