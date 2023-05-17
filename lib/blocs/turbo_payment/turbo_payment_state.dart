part of 'turbo_payment_bloc.dart';

abstract class PaymentState {}

class PaymentInitial extends PaymentState {}

class PaymentLoading extends PaymentState {}

class PaymentLoaded extends PaymentState {
  final int balance;
  final int estimatedStorage;
  final int selectedAmount;
  final String currencyUnit;
  final String dataUnit;

  PaymentLoaded({
    required this.balance,
    required this.estimatedStorage,
    required this.selectedAmount,
    required this.currencyUnit,
    required this.dataUnit,
  });
}

class PaymentError extends PaymentState {
  final String message;

  PaymentError(this.message);
}
