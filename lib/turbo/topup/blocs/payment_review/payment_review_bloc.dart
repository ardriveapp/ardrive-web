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

  PaymentReviewBloc(
    this.turbo,
    PriceEstimate priceEstimate,
  )   : _priceEstimate = priceEstimate,
        super(const PaymentReviewInitial()) {
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
      _emitPaymentReviewLoading(emit);

      logger.d('PaymentReviewFinishPayment');

      turbo.paymentUserInformation = turbo.paymentUserInformation.copyWith(
        email: event.email,
        userAcceptedToReceiveEmails: event.userAcceptedToReceiveEmails,
      );

      final paymentStatus = await turbo.confirmPayment();

      if (paymentStatus == PaymentStatus.success) {
        _emitPaymentSuccess(emit);
      } else {
        _emitPaymentReviewError(emit);
      }
    } catch (e) {
      _emitPaymentReviewError(emit);
    }
  }

  Future<void> _handlePaymentReviewRefreshQuote(
      Emitter<PaymentReviewState> emit) async {
    try {
      _emitPaymentReviewLoadingQuote(emit);

      await _createPaymentIntent();

      _emitPaymentReviewQuoteLoaded(emit);
    } catch (e) {
      _emitPaymentReviewQuoteError(emit);
    }
  }

  Future<void> _handlePaymentReviewLoadPaymentModel(
      Emitter<PaymentReviewState> emit) async {
    try {
      _emitPaymentReviewLoadingPaymentModel(emit);

      turbo.paymentUserInformation = turbo.paymentUserInformation.copyWith(
        email: turbo.paymentUserInformation.email,
      );

      await _createPaymentIntent();

      _emitStatePaymentReviewPaymentModelLoaded(emit);
    } catch (e, s) {
      logger.e('Error loading payment model', e, s);

      _emitPaymentReviewErrorLoadingPaymentModel(emit);
    }
  }

  Future<void> _createPaymentIntent() async {
    _paymentModel = await turbo.createPaymentIntent(
      amount: _priceEstimate.priceInCurrency,
      currency: 'usd',
    );

    _quoteExpirationDate = turbo.quoteExpirationDate;
  }

  void _emitStatePaymentReviewPaymentModelLoaded(
      Emitter<PaymentReviewState> emit) {
    emit(
      PaymentReviewPaymentModelLoaded(
        quoteExpirationDate: _quoteExpirationDate!,
        credits: _getCreditsFromPaymentModel(),
        subTotal: _getSubTotalFromPaymentModel(),
        total: _getTotalFromPaymentModel(),
      ),
    );
  }

  void _emitPaymentReviewLoadingQuote(Emitter emi) {
    emi(
      PaymentReviewLoadingQuote(
        credits: _getCreditsFromPaymentModel(),
        subTotal: _getSubTotalFromPaymentModel(),
        total: _getTotalFromPaymentModel(),
        quoteExpirationDate: _quoteExpirationDate!,
      ),
    );
  }

  void _emitPaymentReviewLoading(Emitter emit) {
    emit(
      PaymentReviewLoading(
        credits: _getCreditsFromPaymentModel(),
        subTotal: _getSubTotalFromPaymentModel(),
        total: _getTotalFromPaymentModel(),
        quoteExpirationDate: _quoteExpirationDate!,
      ),
    );
  }

  void _emitPaymentReviewQuoteLoaded(Emitter<PaymentReviewState> emit) {
    emit(
      PaymentReviewQuoteLoaded(
        credits: _getCreditsFromPaymentModel(),
        subTotal: _getSubTotalFromPaymentModel(),
        total: _getTotalFromPaymentModel(),
        quoteExpirationDate: _quoteExpirationDate!,
      ),
    );
  }

  void _emitPaymentReviewError(Emitter emit) {
    emit(
      PaymentReviewPaymentError(
        errorType: TurboErrorType.unknown,
        quoteExpirationDate: _quoteExpirationDate!,
        credits: _getCreditsFromPaymentModel(),
        subTotal: _getSubTotalFromPaymentModel(),
        total: _getTotalFromPaymentModel(),
      ),
    );
  }

  void _emitPaymentReviewQuoteError(Emitter emit) {
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

  void _emitPaymentSuccess(Emitter emit) {
    emit(
      PaymentReviewPaymentSuccess(
        credits: _getCreditsFromPaymentModel(),
        subTotal: _getSubTotalFromPaymentModel(),
        total: _getTotalFromPaymentModel(),
        quoteExpirationDate: _quoteExpirationDate!,
      ),
    );
  }

  void _emitPaymentReviewErrorLoadingPaymentModel(Emitter emit) {
    emit(
      const PaymentReviewErrorLoadingPaymentModel(
        errorType: TurboErrorType.unknown,
      ),
    );
  }

  void _emitPaymentReviewLoadingPaymentModel(Emitter emit) {
    emit(
      const PaymentReviewLoadingPaymentModel(),
    );
  }

  String _getCreditsFromPaymentModel() => convertCreditsToLiteralString(
      BigInt.from(int.parse(_paymentModel!.topUpQuote.winstonCreditAmount)));

  String _getSubTotalFromPaymentModel() =>
      (_paymentModel!.topUpQuote.paymentAmount / 100).toStringAsFixed(2);

  String _getTotalFromPaymentModel() =>
      (_paymentModel!.topUpQuote.paymentAmount / 100).toStringAsFixed(2);
}
