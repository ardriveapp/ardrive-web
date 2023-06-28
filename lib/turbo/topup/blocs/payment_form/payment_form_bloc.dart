import 'package:ardrive/turbo/topup/models/price_estimate.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'payment_form_event.dart';
part 'payment_form_state.dart';

class PaymentFormBloc extends Bloc<PaymentFormEvent, PaymentFormState> {
  final Turbo turbo;

  PaymentFormBloc(this.turbo, PriceEstimate initialPriceEstimation)
      : super(PaymentFormInitial(initialPriceEstimation,
            _expirationTimeInSeconds(turbo.maxQuoteExpirationDate))) {
    on<PaymentFormEvent>(
      (event, emit) async {
        if (event is PaymentFormLoadSupportedCountries) {
          try {
            emit(PaymentFormLoading(
              state.priceEstimate,
              _expirationTimeInSeconds(turbo.maxQuoteExpirationDate),
            ));

            final supportedCountries = await turbo.getSupportedCountries();

            emit(
              PaymentFormLoaded(
                state.priceEstimate,
                _expirationTimeInSeconds(turbo.maxQuoteExpirationDate),
                supportedCountries,
              ),
            );
          } catch (e) {
            emit(
              PaymentFormError(
                state.priceEstimate,
                _expirationTimeInSeconds(turbo.maxQuoteExpirationDate),
              ),
            );
          }
        } else if (event is PaymentFormUpdateQuote) {
          try {
            emit(
              PaymentFormLoadingQuote(
                state.priceEstimate,
                _expirationTimeInSeconds(
                  turbo.maxQuoteExpirationDate,
                ),
                (state as PaymentFormLoaded).supportedCountries,
              ),
            );

            final priceEstimate = await turbo.refreshPriceEstimate();

            emit(
              PaymentFormQuoteLoaded(
                priceEstimate,
                _expirationTimeInSeconds(turbo.maxQuoteExpirationDate),
                (state as PaymentFormLoaded).supportedCountries,
              ),
            );
          } catch (e, s) {
            logger.e('Error upading the quote.', e, s);

            emit(
              PaymentFormQuoteLoadFailure(
                state.priceEstimate,
                _expirationTimeInSeconds(turbo.maxQuoteExpirationDate),
              ),
            );
          }
        }
      },
    );
  }
}

int _expirationTimeInSeconds(DateTime d) =>
    d.difference(DateTime.now()).inSeconds;
