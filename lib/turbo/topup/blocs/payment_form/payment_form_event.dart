part of 'payment_form_bloc.dart';

abstract class PaymentFormEvent extends Equatable {
  const PaymentFormEvent();

  @override
  List<Object> get props => [];
}

class PaymentFormPrePopulateFields extends PaymentFormEvent {}

class PaymentFormUpdateQuote extends PaymentFormEvent {}
