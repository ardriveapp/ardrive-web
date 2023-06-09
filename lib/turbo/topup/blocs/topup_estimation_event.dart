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

class ConfirmPayment extends TopupEstimationEvent {
  final String nameOnCard;
  final String cardNumber;
  final String expiryDate;
  final int cvc;
  final String postalCode;
  final String country;
  final String email;

  const ConfirmPayment({
    required this.nameOnCard,
    required this.cardNumber,
    required this.expiryDate,
    required this.cvc,
    required this.postalCode,
    required this.country,
    required this.email,
  });

  @override
  List<Object?> get props => [
        nameOnCard,
        cardNumber,
        expiryDate,
        cvc,
        postalCode,
        country,
        email,
      ];
}
