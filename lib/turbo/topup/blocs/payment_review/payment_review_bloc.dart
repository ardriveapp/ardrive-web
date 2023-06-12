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
        super(PaymentReviewInitial(paymentUserInformation)) {
    on<PaymentReviewEvent>((event, emit) async {
      if (event is PaymentReviewFinishPayment) {
        await _handlePaymentReviewFinishPayment(emit);
      } else if (event is PaymentReviewRefreshQuote) {
        await _handlePaymentReviewRefreshQuote(emit);
      } else if (event is PaymentReviewLoadPaymentModel) {
        await _handlePaymentReviewLoadPaymentModel(emit);
      }
    });
  }

  Future<void> _handlePaymentReviewFinishPayment(
      Emitter<PaymentReviewState> emit) async {
    try {
      emit(
        PaymentReviewLoading(
          paymentUserInformation: state.paymentUserInformation,
          credits: _getCreditsFromPaymentModel(),
          subTotal: _getSubTotalFromPaymentModel(),
          total: _getTotalFromPaymentModel(),
          quoteExpirationDate: _quoteExpirationDate!,
        ),
      );

      logger.i('Top up with ${state.paymentUserInformation.toString()}');

      final paymentStatus = await turbo.confirmPayment(
        userInformation: state.paymentUserInformation,
      );
      if (paymentStatus == PaymentStatus.success) {
        emit(
          PaymentReviewPaymentSuccess(
            paymentUserInformation: state.paymentUserInformation,
            credits: _getCreditsFromPaymentModel(),
            subTotal: _getSubTotalFromPaymentModel(),
            total: _getTotalFromPaymentModel(),
            quoteExpirationDate: _quoteExpirationDate!,
          ),
        );
      } else {
        emit(
          PaymentReviewPaymentError(
            paymentUserInformation: state.paymentUserInformation,
            errorType: TurboErrorType.unknown,
          ),
        );
      }
    } catch (e) {
      emit(
        PaymentReviewPaymentError(
          paymentUserInformation: state.paymentUserInformation,
          errorType: TurboErrorType.unknown,
        ),
      );
    }
  }

  Future<void> _handlePaymentReviewRefreshQuote(
      Emitter<PaymentReviewState> emit) async {
    try {
      emit(PaymentReviewLoadingQuote(
        paymentUserInformation: state.paymentUserInformation,
        credits: _getCreditsFromPaymentModel(),
        subTotal: _getSubTotalFromPaymentModel(),
        total: _getTotalFromPaymentModel(),
        quoteExpirationDate: _quoteExpirationDate!,
      ));

      await _createPaymentIntent();

      await Future.delayed(const Duration(seconds: 1));

      emit(
        PaymentReviewQuoteLoaded(
          paymentUserInformation: state.paymentUserInformation,
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
          paymentUserInformation: state.paymentUserInformation,
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
      emit(PaymentReviewLoadingPaymentModel(
        state.paymentUserInformation,
      ));

      await _createPaymentIntent();

      await Future.delayed(const Duration(seconds: 1));

      emit(
        PaymentReviewPaymentModelLoaded(
          paymentUserInformation: state.paymentUserInformation,
          quoteExpirationDate: _quoteExpirationDate!,
          credits: _getCreditsFromPaymentModel(),
          subTotal: _getSubTotalFromPaymentModel(),
          total: _getTotalFromPaymentModel(),
        ),
      );
    } catch (e) {
      logger.e('Error loading payment model: $e');

      emit(PaymentReviewErrorLoadingPaymentModel(
        paymentUserInformation: state.paymentUserInformation,
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
