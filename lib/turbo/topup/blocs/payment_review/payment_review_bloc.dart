import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/topup/models/payment_model.dart';
import 'package:ardrive/turbo/topup/models/price_estimate.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'payment_review_event.dart';
part 'payment_review_state.dart';

class PaymentReviewBloc extends Bloc<PaymentReviewEvent, PaymentReviewState> {
  final Turbo turbo;

  PaymentModel? _paymentModel;
  DateTime? _quoteExpirationDate;
  final PriceEstimate _priceEstimate;

  // Balance data
  BigInt _currentBalance = BigInt.zero;
  BigInt _creditsWinc = BigInt.zero;
  String _storageEstimate = '0 GB';
  String _currentBalanceStorage = '0 GB';
  String _newBalanceStorage = '0 GB';

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
    Emitter<PaymentReviewState> emit,
  ) async {
    try {
      _emitPaymentReviewLoadingQuote(emit);

      await _createPaymentIntent();

      _emitPaymentReviewQuoteLoaded(emit);
    } catch (e) {
      _emitPaymentReviewQuoteError(emit);
    }
  }

  Future<void> _handlePaymentReviewLoadPaymentModel(
    Emitter<PaymentReviewState> emit,
  ) async {
    try {
      _emitPaymentReviewLoadingPaymentModel(emit);

      turbo.paymentUserInformation = turbo.paymentUserInformation.copyWith(
        email: turbo.paymentUserInformation.email,
      );

      await _createPaymentIntent();

      // Fetch balance data
      await _loadBalanceData();

      _emitStatePaymentReviewPaymentModelLoaded(emit);
    } catch (e, s) {
      logger.e('Error loading payment model', e, s);

      _emitPaymentReviewErrorLoadingPaymentModel(emit);
    }
  }

  Future<void> _loadBalanceData() async {
    try {
      // Fetch current Turbo balance
      final balance = await turbo.getBalance();
      _currentBalance = balance;

      // Get credits to receive from payment model
      // Parse directly to BigInt to avoid int overflow on web (JS has 53-bit int limit)
      _creditsWinc =
          BigInt.parse(_paymentModel!.topUpQuote.winstonCreditAmount);

      // Calculate storage estimates using winc per GiB
      // 1 GiB = approximately 1073741824 winc (varies based on pricing)
      // We use the price estimate to get a rough conversion
      final wincPerGiB = await _getWincPerGiB();

      if (wincPerGiB > BigInt.zero) {
        // Storage for credits to receive
        final storageGiB = _creditsWinc.toDouble() / wincPerGiB.toDouble();
        _storageEstimate = _formatStorage(storageGiB);

        // Storage for current balance
        final currentStorageGiB =
            _currentBalance.toDouble() / wincPerGiB.toDouble();
        _currentBalanceStorage = _formatStorage(currentStorageGiB);

        // Storage for new balance
        final newBalance = _currentBalance + _creditsWinc;
        final newStorageGiB = newBalance.toDouble() / wincPerGiB.toDouble();
        _newBalanceStorage = _formatStorage(newStorageGiB);
      }
    } catch (e, s) {
      logger.e('Error loading balance data', e, s);
      // Keep default values on error
    }
  }

  Future<BigInt> _getWincPerGiB() async {
    try {
      // Use the price estimate to calculate winc per GiB
      // priceEstimate contains the credits for the fiat amount
      final priceEstimate = _priceEstimate;
      if (priceEstimate.estimatedStorage > 0) {
        // Calculate winc per GiB based on credits and storage estimate
        final creditsForStorage = priceEstimate.winstonCredits;
        final storageGiB = priceEstimate.estimatedStorage;
        return BigInt.from(creditsForStorage.toDouble() / storageGiB);
      }

      // Fallback: use a reasonable default based on typical pricing
      // ~1.8 trillion winc per GiB (varies with market conditions)
      return BigInt.from(1800000000000);
    } catch (e) {
      logger.e('Error calculating winc per GiB', e);
      return BigInt.from(1800000000000);
    }
  }

  String _formatStorage(double gib) {
    // Use the shared utility for consistent storage formatting
    return formatStorageWithDynamicUnit(gib, includeApprox: false);
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
        promoDiscount: _getPromoDiscountFromModel(),
        creditsWinc: _creditsWinc,
        currentBalance: _currentBalance,
        storageEstimate: _storageEstimate,
        currentBalanceStorage: _currentBalanceStorage,
        newBalanceStorage: _newBalanceStorage,
      ),
    );
  }

  void _emitPaymentReviewLoadingQuote(Emitter emit) {
    emit(
      PaymentReviewLoadingQuote(
        credits: _getCreditsFromPaymentModel(),
        subTotal: _getSubTotalFromPaymentModel(),
        total: _getTotalFromPaymentModel(),
        quoteExpirationDate: _quoteExpirationDate!,
        promoDiscount: _getPromoDiscountFromModel(),
        creditsWinc: _creditsWinc,
        currentBalance: _currentBalance,
        storageEstimate: _storageEstimate,
        currentBalanceStorage: _currentBalanceStorage,
        newBalanceStorage: _newBalanceStorage,
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
        promoDiscount: _getPromoDiscountFromModel(),
        creditsWinc: _creditsWinc,
        currentBalance: _currentBalance,
        storageEstimate: _storageEstimate,
        currentBalanceStorage: _currentBalanceStorage,
        newBalanceStorage: _newBalanceStorage,
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
        promoDiscount: _getPromoDiscountFromModel(),
        creditsWinc: _creditsWinc,
        currentBalance: _currentBalance,
        storageEstimate: _storageEstimate,
        currentBalanceStorage: _currentBalanceStorage,
        newBalanceStorage: _newBalanceStorage,
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
        promoDiscount: _getPromoDiscountFromModel(),
        creditsWinc: _creditsWinc,
        currentBalance: _currentBalance,
        storageEstimate: _storageEstimate,
        currentBalanceStorage: _currentBalanceStorage,
        newBalanceStorage: _newBalanceStorage,
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
        promoDiscount: _getPromoDiscountFromModel(),
        creditsWinc: _creditsWinc,
        currentBalance: _currentBalance,
        storageEstimate: _storageEstimate,
        currentBalanceStorage: _currentBalanceStorage,
        newBalanceStorage: _newBalanceStorage,
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
        promoDiscount: _getPromoDiscountFromModel(),
        creditsWinc: _creditsWinc,
        currentBalance: _currentBalance,
        storageEstimate: _storageEstimate,
        currentBalanceStorage: _currentBalanceStorage,
        newBalanceStorage: _newBalanceStorage,
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

  String _getCreditsFromPaymentModel() => convertWinstonToLiteralString(
      BigInt.from(int.parse(_paymentModel!.topUpQuote.winstonCreditAmount)));

  String? _getSubTotalFromPaymentModel() {
    if (_paymentModel!.topUpQuote.quotedPaymentAmount == null) return null;
    return (_paymentModel!.topUpQuote.quotedPaymentAmount! / 100)
        .toStringAsFixed(2);
  }

  String _getTotalFromPaymentModel() {
    final total = _paymentModel!.topUpQuote.paymentAmount / 100;

    return total.toStringAsFixed(2);
  }

  String? _getPromoDiscountFromModel() {
    final adjustments = _paymentModel!.adjustments;
    if (adjustments.isEmpty) {
      return null;
    }

    final adjustment = adjustments.first;
    final adjustmentAmount = adjustment.adjustmentAmount / 100;

    if (adjustmentAmount == 0) {
      return null;
    }

    // Get the absolute value of the adjustment
    final adjustmentAmountAbs = adjustmentAmount.abs();

    if (adjustmentAmount < 0) {
      return '-\$${adjustmentAmountAbs.toStringAsFixed(2)}';
    } else {
      return '\$${adjustmentAmountAbs.toStringAsFixed(2)}';
    }
  }
}
