part of 'turbo_payment_bloc.dart';

abstract class PaymentState extends Equatable {}

class PaymentInitial extends PaymentState {
  @override
  List<Object?> get props => [];
}

class PaymentLoading extends PaymentState {
  @override
  List<Object?> get props => [];
}

class PaymentLoaded extends PaymentState {
  final BigInt balance;
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

  @override
  List<Object?> get props => [
        balance,
        estimatedStorage,
        selectedAmount,
        currencyUnit,
        dataUnit,
      ];
}

class PaymentError extends PaymentState {
  final String message;

  PaymentError(this.message);

  @override
  List<Object?> get props => [message];
}
