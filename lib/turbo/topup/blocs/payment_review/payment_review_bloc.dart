import 'package:ardrive/blocs/turbo_payment/turbo_payment_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'payment_review_event.dart';
part 'payment_review_state.dart';

class PaymentReviewBloc extends Bloc<PaymentReviewEvent, PaymentReviewState> {
  final Turbo turbo;

  PaymentReviewBloc(this.turbo, PriceEstimate priceEstimate,
      PaymentUserInformation paymentUserInformation)
      : super(PaymentReviewInitial(priceEstimate, paymentUserInformation)) {
    on<PaymentReviewEvent>((event, emit) async {
      if (event is PaymentReviewFinishPayment) {
        try {
          emit(
            PaymentReviewLoading(
              state.priceEstimate,
              state.paymentUserInformation,
            ),
          );

          await turbo.topUp(state.paymentUserInformation);

          emit(
            PaymentReviewPaymentSuccess(
              state.priceEstimate,
              state.paymentUserInformation,
            ),
          );
        } catch (e) {
          emit(
            PaymentReviewPaymentError(
              state.priceEstimate,
              state.paymentUserInformation,
              TurboErrorType.unknown,
            ),
          );
        }
      } else if (event is PaymentReviewRefreshQuote) {
        try {
          emit(PaymentReviewLoadingQuote(
              state.priceEstimate, state.paymentUserInformation));

          final priceEstimate = await turbo.refreshPriceEstimate();

          await Future.delayed(Duration(seconds: 1));

          emit(
            PaymentReviewQuoteLoaded(
              priceEstimate,
              state.paymentUserInformation,
            ),
          );
        } catch (e) {
          emit(
            PaymentReviewQuoteError(
              state.priceEstimate,
              state.paymentUserInformation,
              TurboErrorType.unknown,
            ),
          );
        }
      }
    });
  }
}
