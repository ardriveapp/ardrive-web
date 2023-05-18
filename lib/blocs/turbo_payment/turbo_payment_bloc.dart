import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'turbo_payment_event.dart';
part 'turbo_payment_state.dart';

final presetAmounts = [25, 50, 75, 100];
final supportedCurrencies = ['usd'];
final dataUnits = ['kb', 'mb', 'gb'];

class PriceEstimate {
  final BigInt credits;
  final int priceInCurrency;
  final int estimatedStorage;

  PriceEstimate({
    required this.credits,
    required this.priceInCurrency,
    required this.estimatedStorage,
  });
}

class PaymentBloc extends Bloc<PaymentEvent, PaymentState> {
  final PaymentService paymentService;
  final Wallet wallet;

  PaymentBloc({
    required this.paymentService,
    required this.wallet,
  }) : super(PaymentInitial()) {
    on<PaymentEvent>((event, emit) async {
      if (event is LoadInitialData) {
        emit(PaymentLoading());
        final balance = await paymentService.getBalance(wallet: wallet);

        // TODO: Calculate estiamted storage

        emit(
          PaymentLoaded(
            balance: balance,
            estimatedStorage: 0,
            selectedAmount: 0,
            currencyUnit: supportedCurrencies.first,
            dataUnit: dataUnits.last,
          ),
        );
      } else if (event is PresetAmountSelected) {
      } else if (event is CustomAmountEntered) {
        // Handle custom amount entry here
      } else if (event is CurrencyUnitChanged) {
        // Handle currency unit change here
      } else if (event is DataUnitChanged) {
        // Handle data unit change here
      } else if (event is AddCreditsClicked) {
        // Handle add credits click here
      }
    });
  }
}
