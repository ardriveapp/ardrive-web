import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'turbo_topup_flow_event.dart';
part 'turbo_topup_flow_state.dart';

class TurboTopupFlowBloc
    extends Bloc<TurboTopupFlowEvent, TurboTopupFlowState> {
  int _currentStep = 1;

  TurboTopupFlowBloc() : super(TurboTopupFlowInitial()) {
    on<TurboTopupFlowEvent>((event, emit) async {
      if (event is TurboTopUpShowEstimationView) {
        emit(TurboTopupFlowShowingEstimationView(
          isMovingForward: _currentStep <= event.stepNumber,
        ));
      } else if (event is TurboTopUpShowPaymentFormView) {
        emit(TurboTopupFlowShowingPaymentFormView(
          isMovingForward: _currentStep <= event.stepNumber,
        ));
      } else if (event is TurboTopUpShowSuccessView) {
        emit(TurboTopupFlowShowingSuccessView(
          isMovingForward: _currentStep <= event.stepNumber,
        ));
      } else if (event is TurboTopUpShowPaymentReviewView) {
        emit(TurboTopupFlowShowingPaymentReviewView(
          isMovingForward: _currentStep <= event.stepNumber,
        ));
      }
      _currentStep = event.stepNumber;
    });
  }
}
