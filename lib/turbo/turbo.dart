import 'dart:async';

import 'package:ardrive/blocs/turbo_payment/utils/storage_estimator.dart';
import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:ardrive/turbo/topup/models/price_estimate.dart';
import 'package:ardrive/utils/data_size.dart';
import 'package:ardrive/utils/disposable.dart';
import 'package:ardrive/utils/file_size_units.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:arweave/arweave.dart';

class Turbo extends Disposable {
  final TurboSessionManager _sessionManager;
  final TurboCostCalculator _costCalculator;
  final TurboBalanceRetriever _balanceRetriever;
  final TurboPriceEstimator _priceEstimator;
  final Wallet wallet;

  Turbo({
    required TurboCostCalculator costCalculator,
    required TurboSessionManager sessionManager,
    required TurboBalanceRetriever balanceRetriever,
    required TurboPriceEstimator priceEstimator,
    required this.wallet,
  })  : _balanceRetriever = balanceRetriever,
        _costCalculator = costCalculator,
        _priceEstimator = priceEstimator,
        _sessionManager = sessionManager;

  DateTime get maxQuoteExpirationDate {
    final maxQuoteExpirationTime = _priceEstimator.maxQuoteExpirationTime;

    if (maxQuoteExpirationTime == null) {
      throw Exception(
          'maxQuoteExpirationTime is null. It can happen when you dont computate the balance first.');
    }

    return maxQuoteExpirationTime;
  }

  Stream<bool> get onSessionExpired => _sessionManager.onSessionExpired;

  Stream<PriceEstimate> get onPriceEstimateChanged =>
      _priceEstimator.onPriceEstimateChanged;

  Future<BigInt> getBalance() => _balanceRetriever.getBalance(wallet);

  Future<BigInt> getCostOfOneGB({bool forceGet = false}) =>
      _costCalculator.getCostOfOneGB(forceGet: forceGet);

  PriceEstimate _priceEstimate = PriceEstimate.zero();

  int? _currentAmount;
  String? _currentCurrency;
  FileSizeUnit? _currentDataUnit;

  PriceEstimate get currentPriceEstimate => _priceEstimate;

  Future<PriceEstimate> computePriceEstimate({
    required int currentAmount,
    required String currentCurrency,
    required FileSizeUnit currentDataUnit,
  }) async {
    _currentAmount = currentAmount;
    _currentCurrency = currentCurrency;
    _currentDataUnit = currentDataUnit;

    _priceEstimate = await _priceEstimator.computePriceEstimate(
      currentAmount: currentAmount,
      currentCurrency: currentCurrency,
      currentDataUnit: currentDataUnit,
    );

    return _priceEstimate;
  }

  Future<PriceEstimate> refreshPriceEstimate() async {
    assert(
      _currentAmount != null &&
          _currentCurrency != null &&
          _currentDataUnit != null,
      'Cannot refresh price estimate without first computing it',
    );

    _priceEstimate = await _priceEstimator.computePriceEstimate(
      currentAmount: _currentAmount!,
      currentCurrency: _currentCurrency!,
      currentDataUnit: _currentDataUnit!,
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

  @override
  Future<void> dispose() async {
    logger.d('Disposing turbo');
    _priceEstimator.dispose();
    await _sessionManager.dispose();

    logger.d('Turbo disposed');
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
    return paymentService.getBalance(wallet: wallet);
  }
}

class TurboPriceEstimator extends Disposable {
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

    _maxQuoteExpirationTime = DateTime.now().add(const Duration(minutes: 5));

    return PriceEstimate(
      credits: priceEstimate,
      priceInCurrency: currentAmount,
      estimatedStorage: estimatedStorageForSelectedAmount,
    );
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

const _quoteExpirationTime = Duration(minutes: 5);

Timer _quoteEstimateTimer<T>(Function(Timer) callback) {
  return Timer.periodic(_quoteExpirationTime, (timer) async {
    callback(timer);
  });
}
