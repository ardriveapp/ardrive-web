import 'package:ardrive/blocs/turbo_payment/turbo_payment_bloc.dart';
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
  PaymentUserInformation? _paymentUserInformation;

  TurboTopupFlowBloc(
    this.turbo,
  ) : super(const TurboTopupFlowInitial()) {
    listenToSessionExpiration();
    on<TurboTopupFlowEvent>((event, emit) async {
      if (event is TurboTopUpShowEstimationView) {
        emit(
          TurboTopupFlowShowingEstimationView(
            isMovingForward: _currentStep <= event.stepNumber,
          ),
        );
      } else if (event is TurboTopUpShowPaymentFormView) {
        emit(
          TurboTopupFlowShowingPaymentFormView(
            isMovingForward: _currentStep <= event.stepNumber,
            priceEstimate: turbo.getCurrentPriceEstimate(),
          ),
        );
      } else if (event is TurboTopUpShowSuccessView) {
        emit(
          TurboTopupFlowShowingSuccessView(
            isMovingForward: _currentStep <= event.stepNumber,
          ),
        );
      } else if (event is TurboTopUpShowPaymentReviewView) {
        _paymentUserInformation = event.paymentUserInformation;

        logger.d(_paymentUserInformation.toString());

        emit(
          TurboTopupFlowShowingPaymentReviewView(
            isMovingForward: _currentStep <= event.stepNumber,
            priceEstimate: turbo.getCurrentPriceEstimate(),
            paymentUserInformation: _paymentUserInformation!,
          ),
        );
      } else if (event is TurboTopUpShowSuccessView) {
        emit(TurboTopupFlowShowingSuccessView(
          isMovingForward: _currentStep <= event.stepNumber,
        ));
      } else if (event is TurboTopUpShowSessionExpiredView) {
        emit(TurboTopupFlowShowingErrorView(
          isMovingForward: _currentStep <= event.stepNumber,
          errorType: TurboErrorType.sessionExpired,
        ));
      } else if (event is TurboTopUpShowErrorView) {
        emit(TurboTopupFlowShowingErrorView(
          isMovingForward: _currentStep <= event.stepNumber,
          errorType: event.errorType,
        ));
      }
      _currentStep = event.stepNumber;
    });
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

abstract class PaymentUserInformation extends Equatable {
  final String name;
  final String cardNumber;
  final String expirationDate;
  final String cvv;
  final String country;
  final String postalCode;
  final String? email;

  const PaymentUserInformation({
    required this.name,
    required this.cardNumber,
    required this.expirationDate,
    required this.cvv,
    required this.country,
    required this.postalCode,
    this.email,
  });

  @override
  List<Object> get props => [
        name,
        cardNumber,
        expirationDate,
        cvv,
        country,
        postalCode,
      ];
}

class PaymentUserInformationFromUSA extends PaymentUserInformation {
  final String state;
  final String addressLine1;
  final String addressLine2;

  const PaymentUserInformationFromUSA({
    required this.addressLine1,
    required this.addressLine2,
    required this.state,
    required String name,
    required String cardNumber,
    required String expirationDate,
    required String cvv,
    required String postalCode,
  }) : super(
          name: name,
          cardNumber: cardNumber,
          expirationDate: expirationDate,
          cvv: cvv,
          postalCode: postalCode,
          country: 'US',
        );

  @override
  List<Object> get props => [
        ...super.props,
        state,
        addressLine1,
        addressLine2,
      ];
}
