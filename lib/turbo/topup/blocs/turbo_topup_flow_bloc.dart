import 'package:ardrive/blocs/turbo_payment/turbo_payment_bloc.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'turbo_topup_flow_event.dart';
part 'turbo_topup_flow_state.dart';

class TurboTopupFlowBloc
    extends Bloc<TurboTopupFlowEvent, TurboTopupFlowState> {
  int _currentStep = 1;
  final Turbo turbo;

  TurboTopupFlowBloc(this.turbo) : super(const TurboTopupFlowInitial()) {
    on<TurboTopupFlowEvent>((event, emit) async {
      if (event is TurboTopUpShowEstimationView) {
        emit(TurboTopupFlowShowingEstimationView(
          isMovingForward: _currentStep <= event.stepNumber,
        ));
      } else if (event is TurboTopUpShowPaymentFormView) {
        emit(
          TurboTopupFlowShowingPaymentFormView(
            isMovingForward: _currentStep <= event.stepNumber,
            priceEstimate: turbo.getCurrentPriceEstimate(),
          ),
        );
      }
      _currentStep = event.stepNumber;
    });
  }
}
