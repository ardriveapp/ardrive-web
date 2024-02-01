import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/utils/logger.dart';
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
    try {
      emit(TurboBalanceLoading());

      final balance = await paymentService.getBalance(wallet: wallet);

      emit(TurboBalanceSuccessState(balance: balance));
    } catch (e) {
      logger.e('Error getting balance', e);

      /// Wait for the animation to finish
      await Future.delayed(const Duration(milliseconds: 500));

      if (e is TurboUserNotFound) {
        emit(NewTurboUserState());
      } else {
        emit(TurboBalanceErrorState());
      }
    }
  }
}
