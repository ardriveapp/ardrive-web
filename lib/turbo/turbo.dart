import 'dart:async';

import 'package:ardrive/blocs/turbo_payment/utils/storage_estimator.dart';
import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/topup/models/price_estimate.dart';
import 'package:ardrive/utils/data_size.dart';
import 'package:ardrive/utils/file_size_units.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

class Turbo {
  Turbo({required this.paymentService, required this.wallet})
      : _initialSessionTime = DateTime.now() {
    _startSessionExpirationListener();
  }

  final PaymentService paymentService;
  final Wallet wallet;
  late final DateTime _initialSessionTime;
  final _sessionExpiredController = StreamController<bool>();
  BigInt? _costOfOneGb;
  DateTime? _lastFetchTime;

  int _currentAmount = 0;
  String _currentCurrency = 'usd';
  BigInt _currentBalance = BigInt.from(0);
  FileSizeUnit _currentDataUnit = FileSizeUnit.gigabytes;

  PriceEstimate _priceEstimate = PriceEstimate(
    credits: BigInt.from(0),
    priceInCurrency: 0,
    estimatedStorage: 0,
  );

  // Getters
  DateTime get initialSessionTime => _initialSessionTime;
  DateTime get maxSessionTime =>
      _initialSessionTime.add(const Duration(minutes: 2));
  int get currentAmount => _currentAmount;
  String get currentCurrency => _currentCurrency;
  BigInt get currentBalance => _currentBalance;
  FileSizeUnit get currentDataUnit => _currentDataUnit;
  PriceEstimate get priceEstimate => _priceEstimate;
  Stream<bool> get onSessionExpired => _sessionExpiredController.stream;

  void _startSessionExpirationListener() {
    Timer.periodic(const Duration(seconds: 5), (timer) {
      logger.d('Checking if session is expired');

      final currentTime = DateTime.now();
      if (currentTime.isAfter(maxSessionTime)) {
        _sessionExpiredController.add(true);
        timer.cancel();
      }
    });
  }

  // Cost related methods
  Future<BigInt> getCostOfOneGB({bool forceGet = false}) async {
    final currentTime = DateTime.now();
    if (!forceGet && _costOfOneGb != null && _lastFetchTime != null) {
      final difference = currentTime.difference(_lastFetchTime!);
      if (difference.inMinutes < 10) {
        return _costOfOneGb!;
      }
    }

    _costOfOneGb =
        await paymentService.getPriceForBytes(byteSize: const GiB(1).size);
    _lastFetchTime = currentTime;

    return _costOfOneGb!;
  }

  // Balance related methods
  Future<BigInt> getBalance() async {
    if (_currentBalance != BigInt.from(0)) {
      return _currentBalance;
    }

    _currentBalance = await paymentService.getBalance(wallet: wallet);

    return _currentBalance;
  }

  // Price estimate methods
  PriceEstimate getCurrentPriceEstimate() {
    return _priceEstimate;
  }

  Future<PriceEstimate> computePriceEstimate({
    required int currentAmount,
    required String currentCurrency,
    required FileSizeUnit currentDataUnit,
  }) async {
    try {
      final int correctAmount = currentAmount * 100;

      final priceEstimate = await paymentService.getPriceForFiat(
        currency: currentCurrency,
        amount: correctAmount,
      );

      final estimatedStorageForSelectedAmount =
          computeStorageEstimateForCredits(
        credits: priceEstimate,
        outputDataUnit: currentDataUnit,
      );

      return PriceEstimate(
        credits: priceEstimate,
        priceInCurrency: currentAmount,
        estimatedStorage: await estimatedStorageForSelectedAmount,
      );
    } catch (e) {
      logger.e(e);
      // You might want to do some error handling here
      rethrow;
    }
  }

  Future<PriceEstimate> computePriceEstimateAndUpdate({
    required int currentAmount,
    required String currentCurrency,
    required FileSizeUnit currentDataUnit,
  }) async {
    try {
      _currentAmount = currentAmount;
      _currentCurrency = currentCurrency;
      _currentDataUnit = currentDataUnit;

      _priceEstimate = await computePriceEstimate(
        currentAmount: currentAmount,
        currentCurrency: currentCurrency,
        currentDataUnit: currentDataUnit,
      );

      return _priceEstimate;
    } catch (e) {
      logger.e(e);
      // You might want to do some error handling here
      rethrow;
    }
  }

  Future<PriceEstimate> refreshPriceEstimate() async {
    _costOfOneGb = await getCostOfOneGB(
      forceGet: true,
    );

    return await computePriceEstimate(
      currentAmount: _currentAmount,
      currentCurrency: _currentCurrency,
      currentDataUnit: _currentDataUnit,
    );
  }

  // Storage estimate method
  Future<double> computeStorageEstimateForCredits({
    required BigInt credits,
    required FileSizeUnit outputDataUnit,
  }) async {
    final estimatedStorageInBytes =
        FileStorageEstimator.computeStorageEstimateForCredits(
      credits: credits,
      costOfOneGb: _costOfOneGb ?? await getCostOfOneGB(),
      outputDataUnit: outputDataUnit,
    );

    return estimatedStorageInBytes;
  }

  // Payment related method
  Future topUp(
    PaymentUserInformation paymentUserInformation,
  ) async {
    try {
      final correctAmount = _currentAmount * 100;
      // final _card = CardDetails(
      //   cvc: '123',
      //   expirationMonth: 6,
      //   expirationYear: 26,
      //   number: '4242424242424242',
      // );

      // TODO: implement o turbo class
      final paymentIntentResult =
          await paymentService.topUp(wallet: wallet, amount: correctAmount);

      logger.d(paymentIntentResult.toString());
      logger.d(paymentIntentResult['client_secret']);

      if (paymentUserInformation is PaymentUserInformationFromUSA) {
        // final billingDetails = const BillingDetails(
        //   email: 'email@stripe.com',
        //   phone: '+48888000888',
        //   address: Address(
        //     city: 'Houston',
        //     country: 'US',
        //     line1: '1459  Circle Drive',
        //     line2: '',
        //     state: 'Texas',
        //     postalCode: '77063',
        //   ),
        // ); // mocked data for tests

        //   // 2. Create payment method
        //   final paymentMethod = await Stripe.instance.createPaymentMethod(
        //       params: PaymentMethodParams.card(
        //     paymentMethodData: PaymentMethodData(
        //       billingDetails: billingDetails,
        //     ),
        //   ));

        //   if (paymentIntentResult['clientSecret'] != null &&
        //       paymentIntentResult['requiresAction'] == true) {
        //     // 4. if payment requires action calling handleNextAction
        //     final paymentIntent = await Stripe.instance
        //         .handleNextAction(paymentIntentResult['clientSecret']);

        //     if (paymentIntent.status ==
        //         PaymentIntentsStatus.RequiresConfirmation) {
        //       // 5. Call API to confirm intent
        //       final paymentIntent = await Stripe.instance
        //           .handleNextAction(paymentIntentResult['clientSecret']);

        //       logger.d(paymentIntent.toJson().toString());
        //     }
        //   }

        // 3. call API to create PaymentIntent
        final paymentInfo = paymentUserInformation;

        final billing = BillingDetails(
          name: paymentInfo.name,
          // email: paymentInfo.email,
          // address: Address(
          //   country: paymentUserInformation.country,
          //   line2: paymentInfo.addressLine2,
          //   line1: paymentInfo.addressLine1,
          //   city: paymentInfo.addressLine1,
          //   postalCode: paymentUserInformation.postalCode,
          //   state: paymentInfo.state,
          // ),
        );

        logger.d('Billing details: ${billing.toString()}');
        
        final paymentIntent = await Stripe.instance.confirmPayment(
          paymentIntentClientSecret: paymentIntentResult['client_secret'],
          data: PaymentMethodParams.card(
            paymentMethodData: PaymentMethodData(billingDetails: billing),
          ),
        );

        logger.d(paymentIntent.toJson().toString());
      }
    } catch (e) {
      logger.e(e);
      rethrow;
    }
  }

  void dispose() {}
}
