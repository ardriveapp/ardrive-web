import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/logger/logger.dart';
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
  final double estimatedStorage;

  PriceEstimate({
    required this.credits,
    required this.priceInCurrency,
    required this.estimatedStorage,
  });
}

class TurboTopUpEstimationBloc extends Bloc<PaymentEvent, PaymentState> {
  final Turbo turbo;

  FileSizeUnit _currentDataUnit = FileSizeUnit.gigabytes;
  String _currentCurrency = 'usd';

  // initialize with 0
  int _currentAmount = 0;

  String get currentCurrency => _currentCurrency;
  int get currentAmount => _currentAmount;
  FileSizeUnit get currentDataUnit => _currentDataUnit;

  late BigInt costOfOneGb;

  TurboTopUpEstimationBloc({
    required this.turbo,
  }) : super(PaymentInitial()) {
    on<PaymentEvent>((event, emit) async {
      if (event is LoadInitialData) {
        try {
          await _computePriceEstimate(
            emit,
            currentAmount: 0,
            currentCurrency: currentCurrency,
            currentDataUnit: currentDataUnit,
          );
        } catch (e) {
          logger.e(e);
          emit(PaymentError());
        }
      } else if (event is FiatAmountSelected) {
        _currentAmount = event.amount;

        await _computePriceEstimate(
          emit,
          currentAmount: _currentAmount,
          currentCurrency: currentCurrency,
          currentDataUnit: currentDataUnit,
        );
      } else if (event is CurrencyUnitChanged) {
        _currentCurrency = event.currencyUnit;

        await _computePriceEstimate(
          emit,
          currentAmount: _currentAmount,
          currentCurrency: currentCurrency,
          currentDataUnit: currentDataUnit,
        );
      } else if (event is DataUnitChanged) {
        _currentDataUnit = event.dataUnit;

        await _computePriceEstimate(
          emit,
          currentAmount: _currentAmount,
          currentCurrency: currentCurrency,
          currentDataUnit: currentDataUnit,
        );
      } else if (event is AddCreditsClicked) {
        // Handle add credits click here
      }
    });
  }

  Future<void> _computePriceEstimate(
    Emitter emit, {
    required int currentAmount,
    required String currentCurrency,
    required FileSizeUnit currentDataUnit,
  }) async {
    costOfOneGb = await turbo.getCostOfOneGB();

    BigInt balance;

    try {
      balance = await turbo.getBalance();
    } catch (e) {
      logger.e(e);
      balance = BigInt.zero;
    }

    final priceEstimate = await turbo.computePriceEstimateAndUpdate(
      currentAmount: currentAmount,
      currentCurrency: currentCurrency,
      currentDataUnit: currentDataUnit,
    );

    final estimatedStorageForBalance = turbo.computeStorageEstimateForCredits(
      credits: balance,
      outputDataUnit: currentDataUnit,
    );

    emit(
      PaymentLoaded(
        balance: balance,
        estimatedStorageForBalance:
            estimatedStorageForBalance.toStringAsFixed(2),
        selectedAmount: priceEstimate.priceInCurrency,
        creditsForSelectedAmount: priceEstimate.credits,
        estimatedStorageForSelectedAmount:
            priceEstimate.estimatedStorage.toStringAsFixed(2),
        currencyUnit: currentCurrency,
        dataUnit: currentDataUnit,
      ),
    );
  }
}
