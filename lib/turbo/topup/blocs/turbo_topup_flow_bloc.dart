import 'package:ardrive/turbo/models/payment_user_information.dart';
import 'package:ardrive/turbo/topup/models/price_estimate.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'turbo_topup_flow_event.dart';
part 'turbo_topup_flow_state.dart';

class TurboTopupFlowBloc
    extends Bloc<TurboTopupFlowEvent, TurboTopupFlowState> {
  int _currentStep = 1;
  final Turbo turbo;

  TurboTopupFlowBloc(
    this.turbo,
  ) : super(const TurboTopupFlowInitial()) {
    listenToSessionExpiration();
    on<TurboTopupFlowEvent>(
      (event, emit) async {
        if (event is TurboTopUpShowEstimationView) {
          emit(
            TurboTopupFlowShowingEstimationView(
              isMovingForward: _currentStep <= event.stepNumber,
            ),
          );
        } else if (event is TurboTopUpShowPaymentFormView) {
          String? promoCode;
          if (state is TurboTopupFlowShowingPaymentFormView) {
            promoCode =
                (state as TurboTopupFlowShowingPaymentFormView).promoCode;
          } else if (state is TurboTopupFlowShowingPaymentReviewView) {
            promoCode =
                (state as TurboTopupFlowShowingPaymentReviewView).promoCode;
          }
          emit(
            TurboTopupFlowShowingPaymentFormView(
              isMovingForward: _currentStep <= event.stepNumber,
              priceEstimate: turbo.currentPriceEstimate,
              promoCode: promoCode,
            ),
          );
        } else if (event is TurboTopUpShowSuccessView) {
          emit(
            TurboTopupFlowShowingSuccessView(
              isMovingForward: _currentStep <= event.stepNumber,
            ),
          );
        } else if (event is TurboTopUpShowPaymentReviewView) {
          turbo.paymentUserInformation = PaymentUserInformation.create(
            name: event.name,
            country: event.country,
            userAcceptedToReceiveEmails: false,
          );

          String? promoCode;
          if (state is TurboTopupFlowShowingPaymentFormView) {
            promoCode =
                (state as TurboTopupFlowShowingPaymentFormView).promoCode;
          } else if (state is TurboTopupFlowShowingPaymentReviewView) {
            promoCode =
                (state as TurboTopupFlowShowingPaymentReviewView).promoCode;
          }

          emit(
            TurboTopupFlowShowingPaymentReviewView(
              isMovingForward: _currentStep <= event.stepNumber,
              priceEstimate: turbo.currentPriceEstimate,
              promoCode: promoCode,
            ),
          );
        } else if (event is TurboTopUpShowSuccessView) {
          emit(
            TurboTopupFlowShowingSuccessView(
              isMovingForward: _currentStep <= event.stepNumber,
            ),
          );
        } else if (event is TurboTopUpShowSessionExpiredView) {
          emit(
            TurboTopupFlowShowingErrorView(
              isMovingForward: _currentStep <= event.stepNumber,
              errorType: TurboErrorType.sessionExpired,
            ),
          );
        } else if (event is TurboTopUpShowErrorView) {
          emit(
            TurboTopupFlowShowingErrorView(
              isMovingForward: _currentStep <= event.stepNumber,
              errorType: event.errorType,
            ),
          );
        }
        _currentStep = event.stepNumber;
      },
    );
  }

  void listenToSessionExpiration() {
    turbo.onSessionExpired.listen((isExpired) {
      logger.d('Session expired: $isExpired');
      if (isExpired) {
        add(const TurboTopUpShowSessionExpiredView());
      }
    });
  }
}
