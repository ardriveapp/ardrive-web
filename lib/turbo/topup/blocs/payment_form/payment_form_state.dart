part of 'payment_form_bloc.dart';

abstract class PaymentFormState extends Equatable {
  const PaymentFormState(
    this.priceEstimate,
    this.quoteExpirationTimeInSeconds,
  );

  final PriceEstimate priceEstimate;
  final int quoteExpirationTimeInSeconds;

  @override
  List<Object> get props => [
        priceEstimate,
        quoteExpirationTimeInSeconds,
      ];
}

class PaymentFormInitial extends PaymentFormState {
  const PaymentFormInitial(super.priceEstimate, super.quoteExpirationTime);
}

class PaymentFormPopulatingFieldsForTesting extends PaymentFormState {
  const PaymentFormPopulatingFieldsForTesting(
      super.priceEstimate, super.quoteExpirationTime);

  @override
  List<Object> get props => [];
}

class PaymentFormLoadingQuote extends PaymentFormState {
  const PaymentFormLoadingQuote(super.priceEstimate, super.quoteExpirationTime);
}

class PaymentFormQuoteLoaded extends PaymentFormState {
  const PaymentFormQuoteLoaded(super.priceEstimate, super.quoteExpirationTime);

  @override
  List<Object> get props => [];
}

class PaymentFormQuoteLoadFailure extends PaymentFormState {
  const PaymentFormQuoteLoadFailure(
    super.priceEstimate,
    super.quoteExpirationTime,
  );

  @override
  List<Object> get props => [priceEstimate, quoteExpirationTimeInSeconds];
}
