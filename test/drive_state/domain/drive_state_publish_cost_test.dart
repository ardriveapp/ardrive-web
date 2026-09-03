import 'dart:async';

import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/drive_state/domain/drive_state_publish_cost.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive/turbo/models/turbo_free_allowance.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive_utils/ardrive_utils.dart' show Winston;
import 'package:arweave/arweave.dart' show Wallet;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pst/pst.dart';

import '../../test_utils/utils.dart';

/// What the estimator promises, and what it must not do to keep that promise.
///
/// `§4.4` makes AR the transport that must always exist, so failing to price
/// AR is fatal and the caller turns it into a refusal. Everything Turbo is the
/// opposite: Turbo is the cheap option, not the required one, and an outage on
/// its side must cost the user the Turbo *choice*, never the artifact. That
/// asymmetry is the whole contract, and it is easy to lose one call at a time —
/// an estimate that throws is an artifact that is never offered for
/// confirmation at all, so a single unguarded Turbo call silently removes the
/// feature from users who were going to pay in AR.
void main() {
  late _MockArweave arweave;
  late _MockPaymentService paymentService;
  late _MockPst pst;
  late _MockTurboBalanceRetriever turboBalanceRetriever;
  late _MockConfigService configService;
  late Wallet wallet;

  setUpAll(() async {
    wallet = getTestWallet();
    registerFallbackValue(wallet);
    registerFallbackValue(BigInt.zero);
  });

  setUp(() {
    arweave = _MockArweave();
    paymentService = _MockPaymentService();
    pst = _MockPst();
    turboBalanceRetriever = _MockTurboBalanceRetriever();
    configService = _MockConfigService();

    when(() => configService.config).thenReturn(
      AppConfig(
        useTurboUpload: true,
        useTurboPayment: true,
        allowedDataItemSizeForTurbo: 500 * 1024 * 1024,
        stripePublishableKey: '',
        arweaveGatewayForDataRequest: const SelectedGateway(
          label: 'Turbo Gateway',
          url: 'https://turbo-gateway.com',
        ),
      ),
    );

    // AR prices fine throughout: these tests are about what happens on the
    // other side.
    when(() => arweave.getPrice(byteSize: any(named: 'byteSize')))
        .thenAnswer((_) async => BigInt.from(1000));
    when(() => arweave.getArUsdConversionRateOrNull())
        .thenAnswer((_) async => 5.0);
    when(() => pst.getPSTFee(any()))
        .thenAnswer((_) async => Winston(BigInt.from(10)));

    when(() =>
            paymentService.getPriceForBytes(byteSize: any(named: 'byteSize')))
        .thenAnswer((_) async => BigInt.from(500));
    when(() => paymentService.getPriceForFiat(
          wallet: any(named: 'wallet'),
          currency: any(named: 'currency'),
          amount: any(named: 'amount'),
        )).thenAnswer(
      (_) async => PriceForFiat(
        winc: BigInt.from(1000000),
        adjustments: const [],
        actualPaymentAmount: 100,
        quotedPaymentAmount: 100,
      ),
    );

    when(() => turboBalanceRetriever.getBalance(any()))
        .thenAnswer((_) async => BigInt.from(1000000));
    when(() => turboBalanceRetriever.getFreeAllowance(any()))
        .thenAnswer((_) async => const TurboFreeAllowance.unknown());
  });

  DriveStatePublishCostEstimator estimator({
    Duration? legTimeout,
    Duration? pstFeeTimeout,
  }) =>
      DriveStatePublishCostEstimator(
        arweave: arweave,
        paymentService: paymentService,
        pst: pst,
        turboBalanceRetriever: turboBalanceRetriever,
        configService: configService,
        legTimeout: legTimeout,
        pstFeeTimeout: pstFeeTimeout,
      );

  Future<DriveStatePublishCost> estimate({
    Duration? legTimeout,
    Duration? pstFeeTimeout,
  }) =>
      estimator(legTimeout: legTimeout, pstFeeTimeout: pstFeeTimeout).estimate(
        sizeInBytes: 1024,
        wallet: wallet,
        walletBalance: BigInt.from(1000000),
      );

  /// A call that neither returns nor throws, which is the case a `try`/`catch`
  /// cannot see.
  Future<T> neverAnswers<T>() => Completer<T>().future;

  group('a Turbo failure costs the Turbo option, not the estimate', () {
    test('a free-allowance lookup that throws still returns a price', () async {
      // The one Turbo call that was not guarded. `TurboBalanceRetriever`
      // documents that it never throws, but the estimator's contract is its
      // own: it must not be one collaborator's promise away from removing the
      // feature.
      when(() => turboBalanceRetriever.getFreeAllowance(any()))
          .thenThrow(Exception('the payment service is down'));

      final cost = await estimate();

      expect(cost.freeStatus, FreeUploadStatus.notEligible);
      expect(cost.isFree, isFalse);
      // AR priced, so the artifact is still offered — which is the point.
      expect(cost.costEstimateAr.totalCost, greaterThan(BigInt.zero));
      expect(cost.canPayWith(UploadMethod.ar), isTrue);
    });

    test('a quote that throws leaves Turbo off the menu and AR on it',
        () async {
      when(() =>
              paymentService.getPriceForBytes(byteSize: any(named: 'byteSize')))
          .thenThrow(Exception('the payment service is down'));

      final cost = await estimate();

      expect(cost.isTurboUploadPossible, isFalse);
      expect(cost.canPayWith(UploadMethod.turbo), isFalse);
      expect(cost.canPayWith(UploadMethod.ar), isTrue);
      expect(cost.defaultMethod, UploadMethod.ar);
    });

    test('a balance lookup that throws leaves AR on the menu', () async {
      when(() => turboBalanceRetriever.getBalance(any()))
          .thenThrow(Exception('the payment service is down'));

      final cost = await estimate();

      expect(cost.hasNoTurboBalance, isTrue);
      expect(cost.canPayWith(UploadMethod.ar), isTrue);
    });

    test('all three at once still prices the artifact in AR', () async {
      when(() =>
              paymentService.getPriceForBytes(byteSize: any(named: 'byteSize')))
          .thenThrow(Exception('down'));
      when(() => turboBalanceRetriever.getBalance(any()))
          .thenThrow(Exception('down'));
      when(() => turboBalanceRetriever.getFreeAllowance(any()))
          .thenThrow(Exception('down'));

      final cost = await estimate();

      expect(cost.isTurboUploadPossible, isFalse);
      expect(cost.isUnaffordable, isFalse);
      expect(cost.defaultMethod, UploadMethod.ar);
    });
  });

  group('an AR failure is fatal, deliberately', () {
    test('a price that cannot be obtained throws rather than showing zero',
        () async {
      // The caller turns this into a refusal. A confirm button over a blank or
      // invented cost is a permanent purchase the user did not agree to.
      when(() => arweave.getPrice(byteSize: any(named: 'byteSize')))
          .thenThrow(Exception('every gateway refused'));

      expect(estimate(), throwsA(isA<Exception>()));
    });
  });

  group('a leg that never answers is not a leg that hangs the feature', () {
    // The failure this whole file is about has a second form, and it is the
    // one that actually reached a user: a collaborator that never completes.
    // Every guard here was written against *throwing*, and a `try`/`catch` is
    // no guard at all against a future that simply stays pending - the await
    // never returns, the estimate never resolves, and the modal says
    // "Preparing" until the user gives up.
    const short = Duration(milliseconds: 50);

    test('a Turbo price that never answers still leaves AR on offer', () async {
      when(() => paymentService.getPriceForBytes(
            byteSize: any(named: 'byteSize'),
          )).thenAnswer((_) => neverAnswers());

      final cost = await estimate(legTimeout: short);

      // Exactly the outcome a *throwing* Turbo gets. A hang must not be the
      // one Turbo failure that takes the artifact with it.
      expect(cost.isTurboUploadPossible, isFalse);
      expect(cost.defaultMethod, UploadMethod.ar);
      expect(cost.costEstimateAr.totalCost, greaterThan(BigInt.zero));
    });

    test('a community tip that never answers still prices the artifact',
        () async {
      // The call that actually hung in the field. Reading the community
      // contract goes through a chain of oracles and retries, none of which
      // has a deadline of its own, and the fee is optional here - the AR
      // calculator already proceeds without it when it throws. A hang must
      // not be the one form of that failure which costs the user the feature.
      when(() => pst.getPSTFee(any())).thenAnswer((_) => neverAnswers());

      // The leg has to outlive the tip, or the test proves the wrong thing.
      final cost = await estimate(
        legTimeout: const Duration(seconds: 5),
        pstFeeTimeout: short,
      );

      expect(cost.costEstimateAr.totalCost, greaterThan(BigInt.zero));
      expect(cost.costEstimateAr.pstFee, BigInt.zero);
    });

    test('an AR price that never answers fails instead of waiting for ever',
        () async {
      when(() => arweave.getPrice(byteSize: any(named: 'byteSize')))
          .thenAnswer((_) => neverAnswers());

      // Fatal, like every other AR failure - but bounded, so the caller gets
      // to say so rather than sitting behind a spinner with nothing to report.
      await expectLater(
        estimate(legTimeout: short),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}

class _MockArweave extends Mock implements ArweaveService {}

class _MockPaymentService extends Mock implements PaymentService {}

class _MockPst extends Mock implements PstService {}

class _MockTurboBalanceRetriever extends Mock
    implements TurboBalanceRetriever {}

class _MockConfigService extends Mock implements ConfigService {}
