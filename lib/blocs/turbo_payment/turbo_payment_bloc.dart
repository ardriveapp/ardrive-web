import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'turbo_payment_event.dart';
part 'turbo_payment_state.dart';

class PaymentBloc extends Bloc<PaymentEvent, PaymentState> {
  final PaymentService paymentService;

  PaymentBloc(this.paymentService) : super(PaymentInitial()) {
    on<PaymentEvent>((event, emit) {
      if (event is LoadInitialData) {
        // Load initial data here
      } else if (event is PresetAmountSelected) {
        // Handle preset amount selection here
      } else if (event is CustomAmountEntered) {
        // Handle custom amount entry here
      } else if (event is CurrencyUnitChanged) {
        // Handle currency unit change here
      } else if (event is DataUnitChanged) {
        // Handle data unit change here
      } else if (event is AddCreditsClicked) {
        // Handle add credits click here
      }
    });
  }
}
