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

  String _currentDataUnit = dataUnits.last;
  double _currentAmount = presetAmounts.first.toDouble();

  String get currentCurrency => 'usd';
  double get currentAmount => _currentAmount;
  String get currentDataUnit => _currentDataUnit;

  PaymentBloc({
    required this.paymentService,
    required this.wallet,
  }) : super(PaymentInitial()) {
    on<PaymentEvent>((event, emit) async {
      if (event is LoadInitialData) {
        await _recomputePriceEstimate(emit);
      } else if (event is FiatAmountSelected) {
        _currentAmount = event.amount;
        await _recomputePriceEstimate(emit);
      } else if (event is CurrencyUnitChanged) {
        // TODO Handle currency unit change here
      } else if (event is DataUnitChanged) {
        _currentDataUnit = event.dataUnit;
      } else if (event is AddCreditsClicked) {
        // Handle add credits click here
      }
    });
  }

  _recomputePriceEstimate(Emitter emit) async {
    emit(PaymentLoading());
    final balance = await paymentService.getBalance(wallet: wallet);
    final priceEstimate = await paymentService.getPriceForFiat(
      currency: 'usd',
      amount: currentAmount,
    );
    emit(
      PaymentLoaded(
        balance: balance,
        estimatedStorageForBalance: 0, // TODO: Calculate estiamted storage
        selectedAmount: 0,
        creditsForSelectedAmount: priceEstimate,
        estimatedStorageForSelectedAmount: 0,
        currencyUnit: currentCurrency,
        dataUnit: currentDataUnit,
      ),
    );
  }
}
