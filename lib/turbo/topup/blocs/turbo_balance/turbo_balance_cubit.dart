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

  /// A balance that has not come back by then is an error, not a spinner.
  final Duration requestTimeout;

  TurboBalanceCubit({
    required this.paymentService,
    required this.wallet,
    this.requestTimeout = const Duration(seconds: 20),
  }) : super(TurboBalanceInitial());

  Future<void> getBalance() async {
    try {
      emit(TurboBalanceLoading());

      final balance = await paymentService
          .getBalance(wallet: wallet)
          .timeout(requestTimeout);

      // The card that asked can close while the request is out, and a closed
      // cubit throws on emit.
      if (isClosed) return;
      emit(TurboBalanceSuccessState(balance: balance));
    } catch (e) {
      logger.e('Error getting balance', e);

      if (isClosed) return;
      if (e is TurboUserNotFound) {
        emit(NewTurboUserState());
      } else {
        emit(TurboBalanceErrorState());
      }
    }
  }
}
