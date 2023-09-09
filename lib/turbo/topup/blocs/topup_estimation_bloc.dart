import 'package:ardrive/turbo/topup/models/price_estimate.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/file_size_units.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'topup_estimation_event.dart';
part 'topup_estimation_state.dart';

const presetAmounts = [10, 25, 50, 75];
const minAmount = 5;
const maxAmount = 10000; // 10,000
final supportedCurrencies = ['usd'];

class TurboTopUpEstimationBloc
    extends Bloc<TopupEstimationEvent, TopupEstimationState> {
  final Turbo turbo;

  FileSizeUnit _currentDataUnit = FileSizeUnit.gigabytes;
  String _currentCurrency = 'usd';
  double _currentAmount = 0;

  String get currentCurrency => _currentCurrency;
  double get currentAmount => _currentAmount;
  FileSizeUnit get currentDataUnit => _currentDataUnit;
  late BigInt _balance;

  TurboTopUpEstimationBloc({
    required this.turbo,
  }) : super(EstimationInitial()) {
    turbo.onPriceEstimateChanged.listen((priceEstimate) {
      logger.d('price estimate changed: ${priceEstimate.toString()}');
      add(FetchPriceEstimate(priceEstimate));
    });

    on<TopupEstimationEvent>(
      (event, emit) async {
        if (event is LoadInitialData) {
          try {
            emit(EstimationLoading());
            logger.i('initializing the estimation view');
            logger.i('getting the balance');
            await _getBalance();

            logger.i('getting the price estimate');
            await _computeAndUpdatePriceEstimate(
              emit,
              currentAmount: 0,
              currentCurrency: currentCurrency,
              currentDataUnit: currentDataUnit,
              promoCode: turbo.promoCode,
              shouldRethrow: true,
            );
          } catch (e, s) {
            logger.e('error initializing the estimation view', e, s);

            emit(FetchEstimationError());
          }
        } else if (event is FiatAmountSelected) {
          _currentAmount = event.amount;

          await _computeAndUpdatePriceEstimate(
            emit,
            currentAmount: _currentAmount,
            currentCurrency: currentCurrency,
            currentDataUnit: currentDataUnit,
            promoCode: turbo.promoCode,
          );
        } else if (event is CurrencyUnitChanged) {
          _currentCurrency = event.currencyUnit;

          await _computeAndUpdatePriceEstimate(
            emit,
            currentAmount: _currentAmount,
            currentCurrency: currentCurrency,
            currentDataUnit: currentDataUnit,
            promoCode: turbo.promoCode,
          );
        } else if (event is DataUnitChanged) {
          _currentDataUnit = event.dataUnit;

          await _computeAndUpdatePriceEstimate(
            emit,
            currentAmount: _currentAmount,
            currentCurrency: currentCurrency,
            currentDataUnit: currentDataUnit,
            promoCode: turbo.promoCode,
          );
        } else if (event is PromoCodeChanged) {
          final promoCode = turbo.promoCode;
          final stateAsLoaded = state as EstimationLoaded;

          logger.d('Recieved promo code: $promoCode');

          try {
            await _refreshEstimate(
              emit,
              promoCode: promoCode,
            );
          } catch (e, s) {
            logger.e('error updating the promo code', e, s);
            emit(EstimationLoaded(
              balance: stateAsLoaded.balance,
              estimatedStorageForBalance:
                  stateAsLoaded.estimatedStorageForBalance,
              selectedAmount: stateAsLoaded.selectedAmount,
              creditsForSelectedAmount: stateAsLoaded.creditsForSelectedAmount,
              estimatedStorageForSelectedAmount:
                  stateAsLoaded.estimatedStorageForSelectedAmount,
              currencyUnit: stateAsLoaded.currencyUnit,
              dataUnit: stateAsLoaded.dataUnit,
            ));
          }
        } else if (event is FetchPriceEstimate) {
          final estimatedStorageForBalance =
              await turbo.computeStorageEstimateForCredits(
            credits: _balance,
            outputDataUnit: currentDataUnit,
          );

          emit(
            EstimationLoaded(
              balance: _balance,
              estimatedStorageForBalance:
                  estimatedStorageForBalance.toStringAsFixed(2),
              selectedAmount: event.priceEstimate.priceInCurrency,
              creditsForSelectedAmount:
                  event.priceEstimate.estimate.winstonCredits,
              estimatedStorageForSelectedAmount:
                  event.priceEstimate.estimatedStorage.toStringAsFixed(2),
              currencyUnit: currentCurrency,
              dataUnit: currentDataUnit,
            ),
          );
        }
      },
    );
  }

  Future<void> _computeAndUpdatePriceEstimate(
    Emitter emit, {
    required double currentAmount,
    required String currentCurrency,
    required FileSizeUnit currentDataUnit,
    required String? promoCode,
    bool shouldRethrow = false,
  }) async {
    try {
      emit(EstimationLoading());
      final priceEstimate = await turbo.computePriceEstimate(
        currentAmount: currentAmount,
        currentCurrency: currentCurrency,
        currentDataUnit: currentDataUnit,
        promoCode: promoCode,
      );

      final estimatedStorageForBalance =
          await turbo.computeStorageEstimateForCredits(
        credits: _balance,
        outputDataUnit: currentDataUnit,
      );

      logger.i('selected amount: ${priceEstimate.priceInCurrency}');

      emit(
        EstimationLoaded(
          balance: _balance,
          estimatedStorageForBalance:
              estimatedStorageForBalance.toStringAsFixed(2),
          selectedAmount: priceEstimate.priceInCurrency,
          creditsForSelectedAmount: priceEstimate.estimate.winstonCredits,
          estimatedStorageForSelectedAmount:
              priceEstimate.estimatedStorage.toStringAsFixed(2),
          currencyUnit: currentCurrency,
          dataUnit: currentDataUnit,
        ),
      );
    } catch (e, s) {
      logger.e('Error calculating the estimation', e, s);

      if (shouldRethrow) {
        rethrow;
      }

      emit(EstimationLoadError());
    }
  }

  Future<void> _refreshEstimate(
    Emitter emit, {
    required String? promoCode,
  }) async {
    emit(EstimationLoading());
    try {
      final priceEstimate = turbo.currentPriceEstimate;

      final estimatedStorageForBalance =
          await turbo.computeStorageEstimateForCredits(
        credits: _balance,
        outputDataUnit: currentDataUnit,
      );

      logger.i('selected amount: ${priceEstimate.priceInCurrency}');

      emit(
        EstimationLoaded(
          balance: _balance,
          estimatedStorageForBalance:
              estimatedStorageForBalance.toStringAsFixed(2),
          selectedAmount: priceEstimate.priceInCurrency,
          creditsForSelectedAmount: priceEstimate.estimate.winstonCredits,
          estimatedStorageForSelectedAmount:
              priceEstimate.estimatedStorage.toStringAsFixed(2),
          currencyUnit: currentCurrency,
          dataUnit: currentDataUnit,
        ),
      );
    } catch (e, s) {
      logger.e('Error calculating the estimation', e, s);
      rethrow;
    }
  }

  Future<void> _getBalance() async {
    try {
      _balance = await turbo.getBalance();
    } catch (e) {
      logger.e('Error getting the balance', e);
      rethrow;
    }
  }
}
