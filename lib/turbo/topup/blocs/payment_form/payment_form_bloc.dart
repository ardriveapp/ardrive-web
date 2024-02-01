import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/topup/models/price_estimate.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'payment_form_event.dart';
part 'payment_form_state.dart';

class PaymentFormBloc extends Bloc<PaymentFormEvent, PaymentFormState> {
  final Turbo turbo;
  final int Function(DateTime d)? mockExpirationTimeInSeconds;

  PaymentFormBloc(
    this.turbo,
    PriceEstimate initialPriceEstimation, {
    this.mockExpirationTimeInSeconds,
  }) : super(
          PaymentFormInitial(
            initialPriceEstimation,
            _expirationTimeInSeconds(
              turbo.maxQuoteExpirationDate,
              mockExpirationTimeInSeconds: mockExpirationTimeInSeconds,
            ),
          ),
        ) {
    on<PaymentFormLoadSupportedCountries>(_handleLoadSupportedCountries);
    on<PaymentFormUpdateQuote>(_handleUpdateQuote);
    on<PaymentFormUpdatePromoCode>(_handleUpdatePromoCode);
  }

  Future<void> _handleLoadSupportedCountries(
    PaymentFormLoadSupportedCountries event,
    Emitter<PaymentFormState> emit,
  ) async {
    emit(PaymentFormLoading(
      state.priceEstimate,
      _expirationTimeInSeconds(
        turbo.maxQuoteExpirationDate,
        mockExpirationTimeInSeconds: mockExpirationTimeInSeconds,
      ),
    ));

    try {
      final supportedCountries = await turbo.getSupportedCountries();

      emit(
        PaymentFormLoaded(
          state.priceEstimate,
          _expirationTimeInSeconds(
            turbo.maxQuoteExpirationDate,
            mockExpirationTimeInSeconds: mockExpirationTimeInSeconds,
          ),
          supportedCountries,
        ),
      );
    } catch (e) {
      logger.e('Error loading the supported countries.', e);

      emit(
        PaymentFormError(
          state.priceEstimate,
          _expirationTimeInSeconds(
            turbo.maxQuoteExpirationDate,
            mockExpirationTimeInSeconds: mockExpirationTimeInSeconds,
          ),
        ),
      );
    }
  }

  Future<void> _handleUpdateQuote(
    PaymentFormUpdateQuote event,
    Emitter<PaymentFormState> emit,
  ) async {
    emit(
      PaymentFormLoadingQuote(
        state.priceEstimate,
        _expirationTimeInSeconds(
          turbo.maxQuoteExpirationDate,
          mockExpirationTimeInSeconds: mockExpirationTimeInSeconds,
        ),
        (state as PaymentFormLoaded).supportedCountries,
      ),
    );

    try {
      final priceEstimate = await turbo.refreshPriceEstimate(
        promoCode: turbo.promoCode,
      );

      emit(
        PaymentFormQuoteLoaded(
          priceEstimate,
          _expirationTimeInSeconds(
            turbo.maxQuoteExpirationDate,
            mockExpirationTimeInSeconds: mockExpirationTimeInSeconds,
          ),
          (state as PaymentFormLoaded).supportedCountries,
        ),
      );
    } catch (e, s) {
      logger.e('Error upading the quote.', e, s);

      emit(
        PaymentFormQuoteLoadFailure(
          state.priceEstimate,
          _expirationTimeInSeconds(
            turbo.maxQuoteExpirationDate,
            mockExpirationTimeInSeconds: mockExpirationTimeInSeconds,
          ),
        ),
      );
    }
  }

  void _handleUpdatePromoCode(
    PaymentFormUpdatePromoCode event,
    Emitter<PaymentFormState> emit,
  ) async {
    final promoCode = event.promoCode;
    final stateAsLoaded = state as PaymentFormLoaded;

    emit(
      PaymentFormLoaded(
        state.priceEstimate,
        _expirationTimeInSeconds(
          turbo.maxQuoteExpirationDate,
          mockExpirationTimeInSeconds: mockExpirationTimeInSeconds,
        ),
        stateAsLoaded.supportedCountries,
        isFetchingPromoCode: true,
      ),
    );

    try {
      final refreshedPriceEstimate = await turbo.refreshPriceEstimate(
        promoCode: promoCode,
      );

      final isPromoCodeInvalid = promoCode != null &&
          refreshedPriceEstimate.estimate.adjustments.isEmpty;

      emit(
        PaymentFormLoaded(
          refreshedPriceEstimate,
          _expirationTimeInSeconds(
            turbo.maxQuoteExpirationDate,
            mockExpirationTimeInSeconds: mockExpirationTimeInSeconds,
          ),
          stateAsLoaded.supportedCountries,
          isPromoCodeInvalid: isPromoCodeInvalid,
          isFetchingPromoCode: false,
        ),
      );
    } on PaymentServiceInvalidPromoCode catch (_) {
      emit(
        PaymentFormLoaded(
          state.priceEstimate,
          _expirationTimeInSeconds(
            turbo.maxQuoteExpirationDate,
            mockExpirationTimeInSeconds: mockExpirationTimeInSeconds,
          ),
          stateAsLoaded.supportedCountries,
          isPromoCodeInvalid: true,
          isFetchingPromoCode: false,
        ),
      );
    } catch (e) {
      logger.e('Error fetching the promo code.', e);
      emit(
        PaymentFormLoaded(
          state.priceEstimate,
          _expirationTimeInSeconds(
            turbo.maxQuoteExpirationDate,
            mockExpirationTimeInSeconds: mockExpirationTimeInSeconds,
          ),
          stateAsLoaded.supportedCountries,
          isPromoCodeInvalid: false,
          isFetchingPromoCode: false,
          errorFetchingPromoCode: true,
        ),
      );
    }
  }
}

int _expirationTimeInSeconds(
  DateTime d, {
  int Function(DateTime d)? mockExpirationTimeInSeconds,
}) =>
    mockExpirationTimeInSeconds?.call(d) ??
    d.difference(DateTime.now()).inSeconds;
