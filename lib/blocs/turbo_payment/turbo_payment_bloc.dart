import 'package:ardrive/blocs/turbo_payment/utils/storage_estimator.dart';
import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'file_size_units.dart';

part 'turbo_payment_event.dart';
part 'turbo_payment_state.dart';

final presetAmounts = [25, 50, 75, 100];
final supportedCurrencies = ['usd'];

const oneGigbyteInBytes = 1024 * 1024 * 1024;

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

  FileSizeUnit _currentDataUnit = FileSizeUnit.gigabytes;
  String _currentCurrency = 'usd';
  double _currentAmount = presetAmounts.first.toDouble();

  String get currentCurrency => _currentCurrency;
  double get currentAmount => _currentAmount;
  FileSizeUnit get currentDataUnit => _currentDataUnit;

  late BigInt costOfOneGb;

  PaymentBloc({
    required this.paymentService,
    required this.wallet,
  }) : super(PaymentInitial()) {
    on<PaymentEvent>((event, emit) async {
      if (event is LoadInitialData) {
        costOfOneGb = await _getCostOfOneGB();
        await _recomputePriceEstimate(
          emit,
          currentAmount: currentAmount,
          currentCurrency: currentCurrency,
        );
      } else if (event is FiatAmountSelected) {
        _currentAmount = event.amount;
        await _recomputePriceEstimate(
          emit,
          currentAmount: currentAmount,
          currentCurrency: currentCurrency,
        );
      } else if (event is CurrencyUnitChanged) {
        _currentCurrency = event.currencyUnit;
        await _recomputePriceEstimate(
          emit,
          currentAmount: currentAmount,
          currentCurrency: currentCurrency,
        );
      } else if (event is DataUnitChanged) {
        _currentDataUnit = event.dataUnit;
        await _recomputePriceEstimate(
          emit,
          currentAmount: currentAmount,
          currentCurrency: currentCurrency,
        );
      } else if (event is AddCreditsClicked) {
        // Handle add credits click here
      }
    });
  }

  String computeStorageEstimateForCredits({
    required BigInt credits,
    required FileSizeUnit outputDataUnit,
    required BigInt costOfOneGb,
  }) {
    final estimatedStorageInBytes =
        FileStorageEstimator.computeStorageEstimateForCredits(
      credits: credits,
      costOfOneGb: costOfOneGb,
      outputDataUnit: outputDataUnit,
    );

    return estimatedStorageInBytes.toStringAsFixed(2);
  }

  _recomputePriceEstimate(
    Emitter emit, {
    required double currentAmount,
    required String currentCurrency,
  }) async {
    emit(PaymentLoading());
    final balance = await paymentService.getBalance(wallet: wallet);
    final priceEstimate = await paymentService.getPriceForFiat(
      currency: currentCurrency,
      amount: currentAmount,
    );

    //Use COST OF ONE GB to calculate the estimated storage. Scale linearly

    final estimatedStorageForBalance = computeStorageEstimateForCredits(
      credits: balance,
      outputDataUnit: currentDataUnit,
      costOfOneGb: costOfOneGb,
    );

    final estimatedStorageForSelectedAmount = computeStorageEstimateForCredits(
      credits: priceEstimate,
      outputDataUnit: currentDataUnit,
      costOfOneGb: costOfOneGb,
    );

    emit(
      PaymentLoaded(
        balance: balance,
        estimatedStorageForBalance: estimatedStorageForBalance,
        selectedAmount: currentAmount,
        creditsForSelectedAmount: priceEstimate,
        estimatedStorageForSelectedAmount: estimatedStorageForSelectedAmount,
        currencyUnit: currentCurrency,
        dataUnit: currentDataUnit,
      ),
    );
  }

  Future<BigInt> _getCostOfOneGB() async {
    return await paymentService.getPriceForBytes(byteSize: oneGigbyteInBytes);
  }
}
