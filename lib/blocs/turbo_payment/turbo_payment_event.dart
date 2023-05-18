part of 'turbo_payment_bloc.dart';

abstract class PaymentEvent {}

class LoadInitialData extends PaymentEvent {}

class PresetAmountSelected extends PaymentEvent {
  final int amount;

  PresetAmountSelected(this.amount);
}

class CustomAmountEntered extends PaymentEvent {
  final int amount;

  CustomAmountEntered(this.amount);
}

class CurrencyUnitChanged extends PaymentEvent {
  final String currencyUnit;

  CurrencyUnitChanged(this.currencyUnit);
}

class DataUnitChanged extends PaymentEvent {
  final String dataUnit;

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
