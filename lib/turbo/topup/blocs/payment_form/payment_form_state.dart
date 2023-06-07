part of 'payment_form_bloc.dart';

abstract class PaymentFormState extends Equatable {
  const PaymentFormState(
    this.priceEstimate,
  );

  final PriceEstimate priceEstimate;

  @override
  List<Object> get props => [];
}

class PaymentFormInitial extends PaymentFormState {
  const PaymentFormInitial(super.priceEstimate);
}

class PaymentFormPopulatingFieldsForTesting extends PaymentFormState {
  const PaymentFormPopulatingFieldsForTesting(super.priceEstimate);

  @override
  List<Object> get props => [];
}

class PaymentFormLoadingQuote extends PaymentFormState {
  PaymentFormLoadingQuote(super.priceEstimate);
}

class PaymentFormQuoteLoaded extends PaymentFormState {
  PaymentFormQuoteLoaded(super.priceEstimate);

  @override
  List<Object> get props => [];
}
