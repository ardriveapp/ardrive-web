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

class PaymentFormLoading extends PaymentFormState {
  const PaymentFormLoading(super.priceEstimate, super.quoteExpirationTime);
}

class PaymentFormLoaded extends PaymentFormState {
  final List<String> supportedCountries;

  const PaymentFormLoaded(
    super.priceEstimate,
    super.quoteExpirationTime,
    this.supportedCountries,
  );

  @override
  List<Object> get props => [];
}

class PaymentFormPopulatingFieldsForTesting extends PaymentFormLoaded {
  const PaymentFormPopulatingFieldsForTesting(
    super.priceEstimate,
    super.quoteExpirationTime,
    super.supportedCountries,
  );

  @override
  List<Object> get props => [];
}

class PaymentFormLoadingQuote extends PaymentFormLoaded {
  const PaymentFormLoadingQuote(
    super.priceEstimate,
    super.quoteExpirationTime,
    super.supportedCountries,
  );
}

class PaymentFormQuoteLoaded extends PaymentFormLoaded {
  const PaymentFormQuoteLoaded(
    super.priceEstimate,
    super.quoteExpirationTime,
    super.supportedCountries,
  );

  @override
  List<Object> get props => [];
}

class PaymentFormError extends PaymentFormState {
  const PaymentFormError(
    super.priceEstimate,
    super.quoteExpirationTime,
  );

  @override
  List<Object> get props => [];
}
