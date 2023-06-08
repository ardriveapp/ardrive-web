import 'dart:async';

import 'package:ardrive/blocs/turbo_payment/utils/storage_estimator.dart';
import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:ardrive/turbo/topup/models/price_estimate.dart';
import 'package:ardrive/utils/data_size.dart';
import 'package:ardrive/utils/file_size_units.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:arweave/arweave.dart';

class Turbo {
  final TurboSessionManager sessionManager;
  final TurboCostCalculator costCalculator;
  final TurboBalanceRetriever balanceRetriever;
  final TurboPriceEstimator priceEstimator;

  Turbo({
    required this.sessionManager,
    required this.costCalculator,
    required this.balanceRetriever,
    required this.priceEstimator,
  });

  Stream<bool> get onSessionExpired => sessionManager.onSessionExpired;
  Stream<PriceEstimate> get onPriceEstimateChanged =>
      priceEstimator.onPriceEstimateChanged;

  Future<BigInt> getBalance() => balanceRetriever.getBalance();
  Future<BigInt> getCostOfOneGB({bool forceGet = false}) =>
      costCalculator.getCostOfOneGB(forceGet: forceGet);
  PriceEstimate get currentPriceEstimate => priceEstimator.currentPriceEstimate;

  Future<PriceEstimate> computePriceEstimate({
    required int currentAmount,
    required String currentCurrency,
    required FileSizeUnit currentDataUnit,
  }) =>
      priceEstimator.computePriceEstimate(
        currentAmount: currentAmount,
        currentCurrency: currentCurrency,
        currentDataUnit: currentDataUnit,
      );

  Future<double> computeStorageEstimateForCredits({
    required BigInt credits,
    required FileSizeUnit outputDataUnit,
  }) {
    return priceEstimator.computeStorageEstimateForCredits(
      credits: credits,
      outputDataUnit: outputDataUnit,
    );
  }

  Future<void> dispose() async {
    logger.d('Disposing turbo');
    await sessionManager.dispose();
    await priceEstimator.dispose();

    logger.d('Turbo disposed');
  }
}

class TurboSessionManager {
  final _sessionExpiredController = StreamController<bool>();

  late final DateTime _initialSessionTime;
  late Timer _sessionExpirationTimer;

  // Constructor
  TurboSessionManager() {
    _initialSessionTime = DateTime.now();
    _startSessionExpirationListener();
  }

  DateTime get initialSessionTime => _initialSessionTime;
  DateTime get maxSessionTime =>
      _initialSessionTime.add(const Duration(minutes: 25));

  Stream<bool> get onSessionExpired => _sessionExpiredController.stream;

  void _startSessionExpirationListener() {
    _sessionExpirationTimer =
        Timer.periodic(const Duration(seconds: 5), (timer) {
      logger.d('Checking if session is expired');

      final currentTime = DateTime.now();
      if (currentTime.isAfter(maxSessionTime)) {
        _sessionExpiredController.add(true);
        timer.cancel();
      }
    });
  }

  Future<void> dispose() async {
    logger.d('Disposing SessionManager');
    _sessionExpirationTimer.cancel();
    await _sessionExpiredController.close();
    logger.d('SessionManager disposed');
  }
}

class TurboCostCalculator {
  final PaymentService paymentService;

  DateTime? _lastCostOfOneGbFetchTime;
  BigInt? _costOfOneGb;

  TurboCostCalculator({required this.paymentService});

  Future<BigInt> getCostOfOneGB({bool forceGet = false}) async {
    final currentTime = DateTime.now();

    if (!forceGet &&
        _costOfOneGb != null &&
        _lastCostOfOneGbFetchTime != null) {
      final difference = currentTime.difference(_lastCostOfOneGbFetchTime!);
      if (difference.inMinutes < 10) {
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
  final Wallet wallet;

  BigInt _currentBalance = BigInt.from(0);

  TurboBalanceRetriever({required this.paymentService, required this.wallet});

  Future<BigInt> getBalance() async {
    if (_currentBalance != BigInt.from(0)) {
      return _currentBalance;
    }

    _currentBalance = await paymentService.getBalance(wallet: wallet);

    return _currentBalance;
  }
}

class TurboPriceEstimator {
  final PaymentService paymentService;
  final StreamController<PriceEstimate> _priceEstimateController =
      StreamController<PriceEstimate>.broadcast();
  final TurboCostCalculator costCalculator;

  PriceEstimate _priceEstimate = PriceEstimate(
    credits: BigInt.from(0),
    priceInCurrency: 0,
    estimatedStorage: 0,
  );

  TurboPriceEstimator({
    required this.paymentService,
    required this.costCalculator,
  });

  Stream<PriceEstimate> get onPriceEstimateChanged =>
      _priceEstimateController.stream;

  PriceEstimate get currentPriceEstimate => _priceEstimate;

  Future<PriceEstimate> computePriceEstimate({
    required int currentAmount,
    required String currentCurrency,
    required FileSizeUnit currentDataUnit,
  }) async {
    final int correctAmount = currentAmount * 100;

    final priceEstimate = await paymentService.getPriceForFiat(
      currency: currentCurrency,
      amount: correctAmount,
    );

    final estimatedStorageForSelectedAmount =
        await computeStorageEstimateForCredits(
      credits: priceEstimate,
      outputDataUnit: currentDataUnit,
    );

    _priceEstimate = PriceEstimate(
      credits: priceEstimate,
      priceInCurrency: currentAmount,
      estimatedStorage: estimatedStorageForSelectedAmount,
    );

    return _priceEstimate;
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

  Future<void> dispose() async {
    logger.d('Disposing PriceEstimator');
    await _priceEstimateController.close();
    logger.d('PriceEstimator disposed');
  }
}
