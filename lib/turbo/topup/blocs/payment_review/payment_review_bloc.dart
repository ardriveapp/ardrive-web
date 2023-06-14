import 'package:ardrive/turbo/models/payment_user_information.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/topup/models/payment_model.dart';
import 'package:ardrive/turbo/topup/models/price_estimate.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'payment_review_event.dart';
part 'payment_review_state.dart';

class PaymentReviewBloc extends Bloc<PaymentReviewEvent, PaymentReviewState> {
  final Turbo turbo;

  PaymentModel? _paymentModel;
  DateTime? _quoteExpirationDate;
  final PriceEstimate _priceEstimate;

  PaymentReviewBloc(this.turbo, PriceEstimate priceEstimate,
      PaymentUserInformation paymentUserInformation)
      : _priceEstimate = priceEstimate,
        super(PaymentReviewInitial()) {
    on<PaymentReviewEvent>((event, emit) async {
      if (event is PaymentReviewFinishPayment) {
        await _handlePaymentReviewFinishPayment(emit, event);
      } else if (event is PaymentReviewRefreshQuote) {
        await _handlePaymentReviewRefreshQuote(emit);
      } else if (event is PaymentReviewLoadPaymentModel) {
        await _handlePaymentReviewLoadPaymentModel(emit);
      }
    });
  }

  Future<void> _handlePaymentReviewFinishPayment(
    Emitter<PaymentReviewState> emit,
    PaymentReviewFinishPayment event,
  ) async {
    try {
      emit(
        PaymentReviewLoading(
          credits: _getCreditsFromPaymentModel(),
          subTotal: _getSubTotalFromPaymentModel(),
          total: _getTotalFromPaymentModel(),
          quoteExpirationDate: _quoteExpirationDate!,
        ),
      );

      logger.d(event.paymentUserInformation.toString());

      final paymentStatus = await turbo.confirmPayment(
        userInformation: event.paymentUserInformation,
      );

      if (paymentStatus == PaymentStatus.success) {
        emit(
          PaymentReviewPaymentSuccess(
            credits: _getCreditsFromPaymentModel(),
            subTotal: _getSubTotalFromPaymentModel(),
            total: _getTotalFromPaymentModel(),
            quoteExpirationDate: _quoteExpirationDate!,
          ),
        );
      } else {
        emit(
          PaymentReviewPaymentError(
            credits: _getCreditsFromPaymentModel(),
            subTotal: _getSubTotalFromPaymentModel(),
            total: _getTotalFromPaymentModel(),
            errorType: TurboErrorType.unknown,
            quoteExpirationDate: _quoteExpirationDate!,
          ),
        );
      }
    } catch (e) {
      emit(
        PaymentReviewPaymentError(
          credits: _getCreditsFromPaymentModel(),
          subTotal: _getSubTotalFromPaymentModel(),
          total: _getTotalFromPaymentModel(),
          errorType: TurboErrorType.unknown,
          quoteExpirationDate: _quoteExpirationDate!,
        ),
      );
    }
  }

  Future<void> _handlePaymentReviewRefreshQuote(
      Emitter<PaymentReviewState> emit) async {
    try {
      emit(
        PaymentReviewLoadingQuote(
          // paymentUserInformation: state.paymentUserInformation,
          credits: _getCreditsFromPaymentModel(),
          subTotal: _getSubTotalFromPaymentModel(),
          total: _getTotalFromPaymentModel(),
          quoteExpirationDate: _quoteExpirationDate!,
        ),
      );

      await _createPaymentIntent();

      emit(
        PaymentReviewQuoteLoaded(
          credits: _getCreditsFromPaymentModel(),
          subTotal: _getSubTotalFromPaymentModel(),
          total: _getTotalFromPaymentModel(),
          quoteExpirationDate: _quoteExpirationDate!,
        ),
      );
    } catch (e) {
      emit(
        PaymentReviewQuoteError(
          errorType: TurboErrorType.unknown,
          quoteExpirationDate: _quoteExpirationDate!,
          credits: _getCreditsFromPaymentModel(),
          subTotal: _getSubTotalFromPaymentModel(),
          total: _getTotalFromPaymentModel(),
        ),
      );
    }
  }

  Future<void> _handlePaymentReviewLoadPaymentModel(
      Emitter<PaymentReviewState> emit) async {
    try {
      emit(const PaymentReviewLoadingPaymentModel());

      await _createPaymentIntent();

      await Future.delayed(const Duration(seconds: 1));

      emit(
        PaymentReviewPaymentModelLoaded(
          quoteExpirationDate: _quoteExpirationDate!,
          credits: _getCreditsFromPaymentModel(),
          subTotal: _getSubTotalFromPaymentModel(),
          total: _getTotalFromPaymentModel(),
        ),
      );
    } catch (e) {
      logger.e('Error loading payment model: $e');

      emit(const PaymentReviewErrorLoadingPaymentModel(
        errorType: TurboErrorType.unknown,
      ));
    }
  }

  Future<void> _createPaymentIntent() async {
    _paymentModel = await turbo.createPaymentIntent(
      amount: _priceEstimate.priceInCurrency,
      currency: 'usd', // TODO: get more currencies from backend in a follow up
    );

    _quoteExpirationDate = turbo.quoteExpirationDate;
  }

  String _getCreditsFromPaymentModel() => convertCreditsToLiteralString(
      BigInt.from(int.parse(_paymentModel!.topUpQuote.winstonCreditAmount)));

  String _getSubTotalFromPaymentModel() =>
      (_paymentModel!.topUpQuote.paymentAmount / 100).toStringAsFixed(2);

  String _getTotalFromPaymentModel() =>
      (_paymentModel!.topUpQuote.paymentAmount / 100).toStringAsFixed(2);
}
