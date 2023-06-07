import 'package:ardrive/blocs/turbo_payment/turbo_payment_bloc.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'payment_form_event.dart';
part 'payment_form_state.dart';

class PaymentFormBloc extends Bloc<PaymentFormEvent, PaymentFormState> {
  final Turbo turbo;

  PaymentFormBloc(this.turbo, PriceEstimate initialPriceEstimation)
      : super(PaymentFormInitial(initialPriceEstimation)) {
    on<PaymentFormEvent>(
      (event, emit) async {
        if (event is PaymentFormPrePopulateFields) {
          emit(PaymentFormPopulatingFieldsForTesting(state.priceEstimate));
        } else if (event is PaymentFormUpdateQuote) {
          try {
            emit(PaymentFormLoadingQuote(state.priceEstimate));

            final priceEstimate = await turbo.refreshPriceEstimate();

            emit(PaymentFormQuoteLoaded(priceEstimate));
          } catch (e) {
            logger.e(e);
          }
        }
      },
    );
  }
}
