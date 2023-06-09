part of 'topup_estimation_bloc.dart';

abstract class TopupEstimationEvent extends Equatable {
  const TopupEstimationEvent();
}

class LoadInitialData extends TopupEstimationEvent {
  @override
  List<Object?> get props => [];
}

class FiatAmountSelected extends TopupEstimationEvent {
  final int amount;

  const FiatAmountSelected(this.amount);

  @override
  List<Object?> get props => [];
}

class CurrencyUnitChanged extends TopupEstimationEvent {
  final String currencyUnit;

  const CurrencyUnitChanged(this.currencyUnit);

  @override
  List<Object?> get props => [];
}

class DataUnitChanged extends TopupEstimationEvent {
  final FileSizeUnit dataUnit;

  const DataUnitChanged(this.dataUnit);

  @override
  List<Object?> get props => [];
}

class AddCreditsClicked extends TopupEstimationEvent {
  @override
  List<Object?> get props => [];
}

class FetchPriceEstimate extends TopupEstimationEvent {
  final PriceEstimate priceEstimate;

  const FetchPriceEstimate(this.priceEstimate);

  @override
  List<Object?> get props => [];
}
