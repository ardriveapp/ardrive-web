part of 'turbo_payment_bloc.dart';

abstract class PaymentEvent {}

class LoadInitialData extends PaymentEvent {}

class FiatAmountSelected extends PaymentEvent {
  final double amount;

  FiatAmountSelected(this.amount);
}

class CurrencyUnitChanged extends PaymentEvent {
  final String currencyUnit;

  CurrencyUnitChanged(this.currencyUnit);
}

class DataUnitChanged extends PaymentEvent {
  final FileSizeUnit dataUnit;

  DataUnitChanged(this.dataUnit);
}

class AddCreditsClicked extends PaymentEvent {}

class ConfirmPayment extends PaymentEvent {
  final String nameOnCard;
  final String cardNumber;
  final String expiryDate;
  final int cvc;
  final String postalCode;
  final String country;
  final String email;

  ConfirmPayment({
    required this.nameOnCard,
    required this.cardNumber,
    required this.expiryDate,
    required this.cvc,
    required this.postalCode,
    required this.country,
    required this.email,
  });
}
