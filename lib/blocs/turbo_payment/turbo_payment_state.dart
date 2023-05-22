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
  final double estimatedStorageForBalance;
  final double selectedAmount;
  final BigInt creditsForSelectedAmount;
  final double estimatedStorageForSelectedAmount;
  final String currencyUnit;
  final String dataUnit;

  PaymentLoaded({
    required this.balance,
    required this.estimatedStorageForBalance,
    required this.selectedAmount,
    required this.creditsForSelectedAmount,
    required this.estimatedStorageForSelectedAmount,
    required this.currencyUnit,
    required this.dataUnit,
  });

  @override
  List<Object?> get props => [
        balance,
        estimatedStorageForBalance,
        selectedAmount,
        creditsForSelectedAmount,
        estimatedStorageForSelectedAmount,
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
