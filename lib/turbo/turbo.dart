import 'dart:async';

import 'package:ardrive/blocs/turbo_payment/utils/storage_estimator.dart';
import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:ardrive/turbo/topup/models/price_estimate.dart';
import 'package:ardrive/utils/data_size.dart';
import 'package:ardrive/utils/file_size_units.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:arweave/arweave.dart';

class Turbo {
  Turbo({required this.paymentService, required this.wallet})
      : _initialSessionTime = DateTime.now() {
    _startSessionExpirationListener();
  }

  final PaymentService paymentService;
  final Wallet wallet;

  late final DateTime _initialSessionTime;
  late Timer _sessionExpirationTimer;
  final _sessionExpiredController = StreamController<bool>();
  DateTime? _lastFetchTime;

  BigInt? _costOfOneGb;
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
      _initialSessionTime.add(const Duration(minutes: 25));
  int get currentAmount => _currentAmount;
  String get currentCurrency => _currentCurrency;
  BigInt get currentBalance => _currentBalance;
  FileSizeUnit get currentDataUnit => _currentDataUnit;
  PriceEstimate get priceEstimate => _priceEstimate;
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
    final int correctAmount = currentAmount * 100;

    final priceEstimate = await paymentService.getPriceForFiat(
      currency: currentCurrency,
      amount: correctAmount,
    );

    final estimatedStorageForSelectedAmount = computeStorageEstimateForCredits(
      credits: priceEstimate,
      outputDataUnit: currentDataUnit,
    );

    return PriceEstimate(
      credits: priceEstimate,
      priceInCurrency: currentAmount,
      estimatedStorage: estimatedStorageForSelectedAmount,
    );
  }

  Future<PriceEstimate> computePriceEstimateAndUpdate({
    required int currentAmount,
    required String currentCurrency,
    required FileSizeUnit currentDataUnit,
  }) async {
    _currentAmount = currentAmount;
    _currentCurrency = currentCurrency;
    _currentDataUnit = currentDataUnit;

    _priceEstimate = await computePriceEstimate(
      currentAmount: currentAmount,
      currentCurrency: currentCurrency,
      currentDataUnit: currentDataUnit,
    );

    return _priceEstimate;
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
  double computeStorageEstimateForCredits({
    required BigInt credits,
    required FileSizeUnit outputDataUnit,
  }) {
    final estimatedStorageInBytes =
        FileStorageEstimator.computeStorageEstimateForCredits(
      credits: credits,
      costOfOneGb: _costOfOneGb!,
      outputDataUnit: outputDataUnit,
    );

    return estimatedStorageInBytes;
  }

  void dispose() {
    _sessionExpiredController.close();
    _sessionExpirationTimer.cancel();
  }
}
