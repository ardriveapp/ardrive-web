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
  final double? promoDiscountFactor;
  final bool isPromoCodeInvalid;
  final bool isFetchingPromoCode;
  final bool errorFetchingPromoCode;

  const PaymentFormLoaded(
    super.priceEstimate,
    super.quoteExpirationTime,
    this.supportedCountries, {
    this.promoDiscountFactor,
    this.isPromoCodeInvalid = false,
    this.isFetchingPromoCode = false,
    this.errorFetchingPromoCode = false,
  });

  @override
  List<Object> get props => [
        priceEstimate,
        quoteExpirationTimeInSeconds,
        supportedCountries,
        promoDiscountFactor ?? 0,
        isPromoCodeInvalid,
        isFetchingPromoCode,
        errorFetchingPromoCode,
      ];
}

class PaymentFormPopulatingFieldsForTesting extends PaymentFormLoaded {
  const PaymentFormPopulatingFieldsForTesting(
    super.priceEstimate,
    super.quoteExpirationTime,
    super.supportedCountries, {
    super.promoDiscountFactor,
    super.isPromoCodeInvalid,
    super.isFetchingPromoCode,
    super.errorFetchingPromoCode,
  });
}

class PaymentFormLoadingQuote extends PaymentFormLoaded {
  const PaymentFormLoadingQuote(
    super.priceEstimate,
    super.quoteExpirationTime,
    super.supportedCountries, {
    super.promoDiscountFactor,
    super.isPromoCodeInvalid,
    super.isFetchingPromoCode,
    super.errorFetchingPromoCode,
  });
}

class PaymentFormQuoteLoaded extends PaymentFormLoaded {
  const PaymentFormQuoteLoaded(
    super.priceEstimate,
    super.quoteExpirationTime,
    super.supportedCountries, {
    super.promoDiscountFactor,
    super.isPromoCodeInvalid,
    super.isFetchingPromoCode,
    super.errorFetchingPromoCode,
  });
}

class PaymentFormError extends PaymentFormState {
  const PaymentFormError(
    super.priceEstimate,
    super.quoteExpirationTime,
  );

  // TODO: remove unnecdessary
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
