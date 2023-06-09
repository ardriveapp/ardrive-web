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
        if (event is PaymentFormPrePopulateFields) {
          emit(PaymentFormPopulatingFieldsForTesting(state.priceEstimate,
              _expirationTimeInSeconds(turbo.maxQuoteExpirationDate)));
        } else if (event is PaymentFormUpdateQuote) {
          try {
            emit(PaymentFormLoadingQuote(state.priceEstimate,
                _expirationTimeInSeconds(turbo.maxQuoteExpirationDate)));

            final priceEstimate = await turbo.refreshPriceEstimate();

            emit(PaymentFormQuoteLoaded(priceEstimate,
                _expirationTimeInSeconds(turbo.maxQuoteExpirationDate)));
          } catch (e) {
            logger.e(e);
          }
        }
      },
    );
  }
}

int _expirationTimeInSeconds(DateTime d) =>
    d.difference(DateTime.now()).inSeconds;
