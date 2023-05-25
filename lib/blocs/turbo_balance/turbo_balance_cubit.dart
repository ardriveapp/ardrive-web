import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'turbo_balance_state.dart';

class TurboBalanceCubit extends Cubit<TurboBalanceState> {
  final PaymentService paymentService;
  final Wallet wallet;

  TurboBalanceCubit({
    required this.paymentService,
    required this.wallet,
  }) : super(TurboBalanceInitial());

  Future<void> getBalance() async {
    emit(TurboBalanceLoading());
    try {
      final balance = await paymentService.getBalance(wallet: wallet);
      emit(TurboBalanceSuccessState(balance: balance));
    } catch (e) {
      if (e is TurboUserNotFound) {
        emit(NewTurboUserState());
      } else {
        emit(TurboBalanceErrorState());
      }
    }
  }
}
