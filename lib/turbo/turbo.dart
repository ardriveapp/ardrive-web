import 'dart:async';

import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/turbo/models/payment_user_information.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/topup/models/payment_model.dart';
import 'package:ardrive/turbo/topup/models/price_estimate.dart';
import 'package:ardrive/turbo/utils/storage_estimator.dart';
import 'package:ardrive/utils/data_size.dart';
import 'package:ardrive/utils/disposable.dart';
import 'package:ardrive/utils/file_size_units.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

class Turbo extends Disposable {
  Turbo({
    required TurboCostCalculator costCalculator,
    required TurboSessionManager sessionManager,
    required TurboBalanceRetriever balanceRetriever,
    required TurboPriceEstimator priceEstimator,
    required TurboPaymentProvider paymentProvider,
    required Wallet wallet,
    required TurboSupportedCountriesRetriever supportedCountriesRetriever,
  })  : _balanceRetriever = balanceRetriever,
        _costCalculator = costCalculator,
        _priceEstimator = priceEstimator,
        _paymentProvider = paymentProvider,
        _wallet = wallet,
        _sessionManager = sessionManager,
        _supportedCountriesRetriever = supportedCountriesRetriever;

  DateTime get maxQuoteExpirationDate {
    final maxQuoteExpirationTime = _priceEstimator.maxQuoteExpirationTime;

    if (maxQuoteExpirationTime == null) {
      throw Exception(
          'maxQuoteExpirationTime is null. It can happen when you dont computate the balance first.');
    }

    return maxQuoteExpirationTime;
  }

  final TurboSessionManager _sessionManager;
  final TurboCostCalculator _costCalculator;
  final TurboBalanceRetriever _balanceRetriever;
  final TurboPriceEstimator _priceEstimator;
  final TurboPaymentProvider _paymentProvider;
  final TurboSupportedCountriesRetriever _supportedCountriesRetriever;
  final Wallet _wallet;

  PriceEstimate _priceEstimate = PriceEstimate.zero();
  double? _currentAmount;
  String? _currentCurrency;
  FileSizeUnit? _currentDataUnit;
  double? _promoDiscountFactor = 0;

  PaymentUserInformation? _paymentUserInformation;

  PriceEstimate get currentPriceEstimate => _priceEstimate;

  Stream<bool> get onSessionExpired => _sessionManager.onSessionExpired;

  Stream<PriceEstimate> get onPriceEstimateChanged =>
      _priceEstimator.onPriceEstimateChanged;

  Future<BigInt> getBalance() => _balanceRetriever.getBalance(_wallet);

  Future<BigInt> getCostOfOneGB({bool forceGet = false}) =>
      _costCalculator.getCostOfOneGB(forceGet: forceGet);

  set paymentUserInformation(PaymentUserInformation paymentUserInformation) {
    _paymentUserInformation = paymentUserInformation;
  }

  PaymentStatus? _paymentStatus;

  PaymentStatus? get paymentStatus => _paymentStatus;

  PaymentUserInformation get paymentUserInformation {
    if (_paymentUserInformation == null) {
      throw Exception(
          'Payment user information is null. You should set it before calling this method.');
    }

    return _paymentUserInformation!;
  }

  Future<PriceEstimate> computePriceEstimate({
    required double currentAmount,
    required String currentCurrency,
    required FileSizeUnit currentDataUnit,
    required double promoDiscountFactor,
  }) async {
    _currentAmount = currentAmount;
    _currentCurrency = currentCurrency;
    _currentDataUnit = currentDataUnit;
    _promoDiscountFactor = promoDiscountFactor;

    _priceEstimate = await _priceEstimator.computePriceEstimate(
      currentAmount: currentAmount,
      currentCurrency: currentCurrency,
      currentDataUnit: currentDataUnit,
      promoDiscountFactor: promoDiscountFactor,
    );

    return _priceEstimate;
  }

  Future<PriceEstimate> refreshPriceEstimate() async {
    assert(
      _currentAmount != null &&
          _currentCurrency != null &&
          _currentDataUnit != null &&
          _promoDiscountFactor != null,
      'Cannot refresh price estimate without first computing it',
    );

    _priceEstimate = await _priceEstimator.computePriceEstimate(
      currentAmount: _currentAmount!,
      currentCurrency: _currentCurrency!,
      currentDataUnit: _currentDataUnit!,
      promoDiscountFactor: _promoDiscountFactor!,
    );

    return _priceEstimate;
  }

  Future<double> computeStorageEstimateForCredits({
    required BigInt credits,
    required FileSizeUnit outputDataUnit,
  }) {
    return _priceEstimator.computeStorageEstimateForCredits(
      credits: credits,
      outputDataUnit: outputDataUnit,
    );
  }

  PaymentModel? _currentPaymentIntent;

  DateTime? _quoteExpirationDate;

  PaymentModel? get currentPaymentIntent => _currentPaymentIntent;
  DateTime? get quoteExpirationDate => _quoteExpirationDate;

  Future<PaymentModel> createPaymentIntent({
    required double amount,
    required String currency,
  }) async {
    _currentPaymentIntent = await _paymentProvider.createPaymentIntent(
      amount: amount,
      currency: currency,
      wallet: _wallet,
    );

    _quoteExpirationDate = DateTime.parse(
      _currentPaymentIntent!.topUpQuote.quoteExpirationDate,
    ).subtract(
      const Duration(
        seconds: 5,
      ),
    );

    return _currentPaymentIntent!;
  }

  Future<PaymentStatus> confirmPayment() async {
    if (_currentPaymentIntent == null) {
      throw Exception(
          'Current payment intent is null. You should create it before calling this method.');
    }

    logger.d('Confirming payment with payment provider');

    _paymentStatus = await _paymentProvider.confirmPayment(
      paymentUserInformation: paymentUserInformation,
      paymentModel: _currentPaymentIntent!,
    );

    return _paymentStatus!;
  }

  Future<List<String>> getSupportedCountries() =>
      _supportedCountriesRetriever.getSupportedCountries();

  @override
  Future<void> dispose() async {
    logger.d('Disposing turbo');
    _priceEstimator.dispose();
    await _sessionManager.dispose();

    logger.d('Turbo disposed');
  }

  // Future<double?> _getPromoDiscountFactor(String promoCode) async {
  //   // final estimationBloc = context.read<TurboTopUpEstimationBloc>();
  //   if (!_isPromoCodeEmpty()) {
  //     final promoDiscount = await getPromoDiscountFactor(promoCode);
  //     if (promoDiscount != null) {
  //       // setState(() {
  //       //   _promoCode = _promoCodeController.text;
  //       //   _promoDiscountFactor = promoDiscount;
  //       //   estimationBloc.add(PromoCodeChanged(promoDiscount));
  //       // });

  //     } else {
  //       // setState(() {
  //       //   _promoCode = '';
  //       //   _promoCodeInvalid = true;
  //       //   _promoCodeController.clear();
  //       // });
  //     }
  //   }
  // }

  Future<double?> getPromoDiscountFactor(String promoCode) async {
    const validCodes = {
      'ARDRIVE': 1.0,
      'TURBO': 0.5,
      'MATI': 0.1,
    };

    await Future.delayed(const Duration(seconds: 2));

    // Simulate error
    if (promoCode == 'ERROR') throw Exception('Error getting promo code');

    final isValid = validCodes.keys.contains(promoCode);
    return isValid ? validCodes[promoCode] : null;
  }
}

class TurboSessionManager extends Disposable {
  final _sessionExpiredController = StreamController<bool>();

  late final DateTime _initialSessionTime;
  late Timer _sessionExpirationTimer;

  TurboSessionManager() {
    _initialSessionTime = DateTime.now();
    _startSessionExpirationListener();
  }

  DateTime get initialSessionTime => _initialSessionTime;
  DateTime get maxSessionTime =>
      _initialSessionTime.add(const Duration(minutes: 25));

  Stream<bool> get onSessionExpired => _sessionExpiredController.stream;

  void _startSessionExpirationListener() {
    _sessionExpirationTimer = _quoteEstimateTimer((timer) {
      final currentTime = DateTime.now();
      if (currentTime.isAfter(maxSessionTime)) {
        logger.d('Session expired');
        _sessionExpiredController.add(true);
        timer.cancel();
      }
    });
  }

  @override
  Future<void> dispose() async {
    logger.d('Disposing SessionManager');
    _sessionExpirationTimer.cancel();
    _sessionExpiredController.close();
    logger.d('SessionManager disposed');
  }
}

class TurboCostCalculator {
  final PaymentService paymentService;

  DateTime? _lastCostOfOneGbFetchTime;
  BigInt? _costOfOneGb;

  TurboCostCalculator({required this.paymentService});

  /// Returns the cost for the given byte size
  Future<BigInt> getCostForBytes({required int byteSize}) {
    return paymentService.getPriceForBytes(byteSize: byteSize);
  }

  /// Caches the cost for 1GiB for 5 minutes
  Future<BigInt> getCostOfOneGB({
    bool forceGet = false,
  }) async {
    final currentTime = DateTime.now();

    if (!forceGet &&
        _costOfOneGb != null &&
        _lastCostOfOneGbFetchTime != null) {
      final difference = currentTime.difference(_lastCostOfOneGbFetchTime!);
      if (difference.inMinutes < 5) {
        return _costOfOneGb!;
      }
    }

    _costOfOneGb =
        await paymentService.getPriceForBytes(byteSize: const GiB(1).size);

    _lastCostOfOneGbFetchTime = currentTime;

    return _costOfOneGb!;
  }
}

class TurboBalanceRetriever {
  final PaymentService paymentService;

  TurboBalanceRetriever({
    required this.paymentService,
  });

  Future<BigInt> getBalance(Wallet wallet) async {
    try {
      final balance = await paymentService.getBalance(wallet: wallet);
      return balance;
    } catch (e) {
      if (e is TurboUserNotFound) {
        logger.e('Error getting balance', e);
        return BigInt.zero;
      }
      rethrow;
    }
  }
}

class TurboPriceEstimator extends Disposable with ConvertForUSD<BigInt> {
  TurboPriceEstimator({
    required this.paymentService,
    required this.costCalculator,
  }) {
    _startOnPriceEstimateChange();
  }

  final PaymentService paymentService;
  final TurboCostCalculator costCalculator;

  DateTime? _maxQuoteExpirationTime;
  DateTime? get maxQuoteExpirationTime => _maxQuoteExpirationTime;

  Future<PriceEstimate> computePriceEstimate({
    required double currentAmount,
    required String currentCurrency,
    required FileSizeUnit currentDataUnit,
    required double promoDiscountFactor,
  }) async {
    try {
      final double correctAmount = currentAmount * 100;

      final priceEstimate = await paymentService.getPriceForFiat(
        currency: currentCurrency,
        amount: correctAmount,
      );

      final estimatedStorageForSelectedAmount =
          await computeStorageEstimateForCredits(
        credits: priceEstimate,
        outputDataUnit: currentDataUnit,
      );

      _maxQuoteExpirationTime =
          DateTime.now().add(const Duration(minutes: 4, seconds: 55));

      final price = PriceEstimate(
        credits: priceEstimate,
        priceInCurrency: currentAmount,
        estimatedStorage: estimatedStorageForSelectedAmount,
        promoDiscountFactor: promoDiscountFactor,
      );

      _priceEstimateController.add(price);

      return price;
    } catch (e) {
      logger.e('Error computing price estimate', e);
      rethrow;
    }
  }

  @override
  Future<double?> convertForUSD(BigInt value) async {
    // 1 dolar
    final priceEstimate = await paymentService.getPriceForFiat(
      currency: 'usd',
      amount: 100,
    );

    logger.d('Price estimate for 1 dolar: $priceEstimate');

    return value / priceEstimate;
  }

  Future<double> computeStorageEstimateForCredits({
    required BigInt credits,
    required FileSizeUnit outputDataUnit,
  }) async {
    final costOfOneGb = await costCalculator.getCostOfOneGB();

    final estimatedStorageInBytes =
        FileStorageEstimator.computeStorageEstimateForCredits(
      credits: credits,
      costOfOneGb: costOfOneGb,
      outputDataUnit: outputDataUnit,
    );

    return estimatedStorageInBytes;
  }

  late Timer _priceEstimateTimer;

  final StreamController<PriceEstimate> _priceEstimateController =
      StreamController.broadcast();

  Stream<PriceEstimate> get onPriceEstimateChanged =>
      _priceEstimateController.stream;

  void _startOnPriceEstimateChange() {
    _priceEstimateTimer =
        Timer.periodic(const Duration(minutes: 5), (timer) async {
      final priceEstimate = await computePriceEstimate(
        currentAmount: 0,
        currentCurrency: 'usd',
        currentDataUnit: FileSizeUnit.gigabytes,
        promoDiscountFactor: 0,
      );

      _priceEstimateController.add(priceEstimate);
    });
  }

  @override
  dispose() {
    _priceEstimateTimer.cancel();
    _priceEstimateController.close();
  }
}

abstract class TurboPaymentProvider {
  Future<PaymentModel> createPaymentIntent({
    required String currency,
    required double amount,
    required Wallet wallet,
  });

  Future<PaymentStatus> confirmPayment({
    required PaymentUserInformation paymentUserInformation,
    required PaymentModel paymentModel,
  });
}

class StripePaymentProvider implements TurboPaymentProvider {
  final PaymentService paymentService;
  final Stripe stripe;

  StripePaymentProvider({
    required this.paymentService,
    required this.stripe,
  });

  @override
  Future<PaymentModel> createPaymentIntent({
    required String currency,
    required double amount,
    required Wallet wallet,
  }) async {
    final correctAmount = amount * 100;

    return paymentService.getPaymentIntent(
      currency: currency,
      amount: correctAmount,
      wallet: wallet,
    );
  }

  @override
  Future<PaymentStatus> confirmPayment({
    required PaymentUserInformation paymentUserInformation,
    required PaymentModel paymentModel,
  }) async {
    if (DateTime.parse(paymentModel.topUpQuote.quoteExpirationDate)
        .isBefore(DateTime.now())) {
      logger.e('Quote expired');

      return PaymentStatus.quoteExpired;
    }

    logger.d('Confirming payment with Stripe');

    final billingDetails = BillingDetails(
      email: paymentUserInformation.userAcceptedToReceiveEmails
          ? paymentUserInformation.email
          : null,
      name: paymentUserInformation.name,
    );

    final params = PaymentMethodParams.card(
      paymentMethodData: PaymentMethodData(
        billingDetails: billingDetails,
      ),
    );

    final paymentIntent = await stripe.confirmPayment(
      paymentIntentClientSecret: paymentModel.paymentSession.clientSecret,
      data: params,
      receiptEmail: paymentUserInformation.email,
    );

    if (paymentIntent.status == PaymentIntentsStatus.Succeeded) {
      logger.d('Payment succeeded');
      return PaymentStatus.success;
    }

    logger.e('Payment failed with status: ${paymentIntent.status}');
    return PaymentStatus.failed;
  }
}

class TurboSupportedCountriesRetriever {
  final PaymentService paymentService;

  TurboSupportedCountriesRetriever({
    required this.paymentService,
  });

  Future<List<String>> getSupportedCountries() async {
    return paymentService.getSupportedCountries();
  }
}

enum PaymentStatus {
  success,
  failed,
  quoteExpired,
}

const _quoteExpirationTime = Duration(minutes: 5);

Timer _quoteEstimateTimer<T>(Function(Timer) callback) {
  return Timer.periodic(_quoteExpirationTime, (timer) async {
    callback(timer);
  });
}

bool _isStripeInitialized = false;

void initializeStripe(AppConfig appConfig) {
  if (_isStripeInitialized) return;

  logger.d('Initializing Stripe');

  Stripe.publishableKey = appConfig.stripePublishableKey;

  _isStripeInitialized = true;

  logger.d('Stripe initialized');
}
