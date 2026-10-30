import 'dart:typed_data';

import 'package:ardrive/blocs/upload/models/upload_review_summary.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/core/upload/metadata_write_cost.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/turbo/models/turbo_free_allowance.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

class _MockPayments extends Mock implements PaymentService {}

class _MockTurbo extends Mock implements TurboUploadService {}

class _MockArweave extends Mock implements ArweaveService {}

/// One credit, in winston credits.
final _credit = BigInt.from(10).pow(12);

void main() {
  late _MockPayments payments;
  late _MockTurbo turbo;
  late _MockArweave arweave;
  late MetadataWriteCostReader reader;
  final wallet = getTestWallet();

  /// What Turbo charges for one item, and how many winston credits a dollar
  /// buys: so one item costs a hundredth of a cent.
  final perItem = BigInt.from(20000000);
  final perDollar = BigInt.from(200000000000);

  setUpAll(() => registerFallbackValue(getTestWallet()));

  setUp(() {
    payments = _MockPayments();
    turbo = _MockTurbo();
    arweave = _MockArweave();
    reader = MetadataWriteCostReader(
      payments: payments,
      turbo: turbo,
      arweave: arweave,
    );
    when(() => turbo.useTurboUpload).thenReturn(true);
    when(() => turbo.maxFreeItemSizeBytes).thenReturn(5 * 1024 * 1024);
    when(() => payments.getPriceForBytes(byteSize: any(named: 'byteSize')))
        .thenAnswer((_) async => perItem);
    when(() => payments.getPriceForFiat(
          wallet: any(named: 'wallet'),
          amount: any(named: 'amount'),
          currency: any(named: 'currency'),
        )).thenAnswer((_) async => PriceForFiat(
          winc: perDollar,
          adjustments: const [],
          actualPaymentAmount: 100,
          quotedPaymentAmount: 100,
        ));
    when(() => payments.getBalanceAndPaidBy(wallet: any(named: 'wallet')))
        .thenAnswer((_) async =>
            TurboBalanceInterface(balance: _credit, paidBy: const []));
  });

  void balance(BigInt winc, {List<String> paidBy = const []}) =>
      when(() => payments.getBalanceAndPaidBy(wallet: any(named: 'wallet')))
          .thenAnswer((_) async =>
              TurboBalanceInterface(balance: winc, paidBy: paidBy));

  void allowance(TurboFreeAllowance allowance) =>
      when(() => payments.getFreeAllowance(wallet: any(named: 'wallet')))
          .thenAnswer((_) async => allowance);

  Future<UploadReviewSummary> read(
          {bool refused = false, List<int> sizes = const [1800, 2100]}) async =>
      (await reader.read(
        itemSizes: sizes,
        wallet: wallet,
        walletBalance: BigInt.zero,
        refusedByTurbo: refused,
      ))
          .summary;

  group('with Turbo uploads on', () {
    test('free when the free upload allowance covers every item', () async {
      allowance(TurboFreeAllowance.bytes(100 * 1024 * 1024));

      final summary = await read();

      expect(summary.isFree, isTrue);
      expect(summary.isCovered, isTrue);
      expect(summary.method, UploadMethod.turbo);
    });

    test('free whatever the price, when the allowance covers it', () async {
      allowance(TurboFreeAllowance.bytes(100 * 1024 * 1024));
      when(() => payments.getPriceForBytes(byteSize: any(named: 'byteSize')))
          .thenThrow(Exception('no price'));

      final summary = await read();

      expect(summary.isFree, isTrue);
      expect(summary.isCovered, isTrue);
    });

    test('priced per item at the largest size, in credits and dollars',
        () async {
      allowance(const TurboFreeAllowance.disabled());

      final summary = await read();

      verify(() => payments.getPriceForBytes(byteSize: 2100)).called(1);
      expect(summary.isFree, isFalse);
      expect(summary.creditsCost, perItem * BigInt.two);
      expect(summary.usdCost, closeTo(0.0002, 1e-9));
      expect(summary.isCovered, isTrue);
      expect(summary.needsCredits, isFalse);
    });

    test('over the allowance, when it does not cover the whole write',
        () async {
      allowance(TurboFreeAllowance.bytes(3000));

      final summary = await read();

      expect(summary.isFree, isFalse);
      expect(summary.overFreeAllowance, isTrue);
      expect(summary.isCovered, isTrue);
    });

    test('not covered when the credits are short: Add credits', () async {
      allowance(const TurboFreeAllowance.disabled());
      balance(perItem);

      final summary = await read();

      expect(summary.isCovered, isFalse);
      expect(summary.needsCredits, isTrue);
      expect(summary.priceUnavailable, isFalse);
      expect(summary.creditsBalance, perItem);
    });

    test('an account Turbo does not know yet has no credits', () async {
      allowance(const TurboFreeAllowance.disabled());
      when(() => payments.getBalanceAndPaidBy(wallet: any(named: 'wallet')))
          .thenThrow(TurboUserNotFound());

      final summary = await read();

      expect(summary.needsCredits, isTrue);
      expect(summary.creditsBalance, BigInt.zero);
    });

    test('no price when Turbo will not give one', () async {
      allowance(const TurboFreeAllowance.disabled());
      when(() => payments.getPriceForBytes(byteSize: any(named: 'byteSize')))
          .thenThrow(Exception('blocked'));

      final summary = await read();

      expect(summary.priceUnavailable, isTrue);
      expect(summary.isCovered, isFalse);
      expect(summary.needsCredits, isFalse);
    });

    test('no price when the allowance cannot be read', () async {
      when(() => payments.getFreeAllowance(wallet: any(named: 'wallet')))
          .thenThrow(Exception('blocked'));

      final summary = await read();

      expect(summary.isFree, isFalse);
      expect(summary.priceUnavailable, isTrue);
      expect(summary.isCovered, isFalse);
    });

    test('no price when the balance cannot be read', () async {
      allowance(const TurboFreeAllowance.disabled());
      when(() => payments.getBalanceAndPaidBy(wallet: any(named: 'wallet')))
          .thenThrow(Exception('blocked'));

      final summary = await read();

      expect(summary.priceUnavailable, isTrue);
      expect(summary.isCovered, isFalse);
    });

    test('the price in credits when there is no dollar rate', () async {
      allowance(const TurboFreeAllowance.disabled());
      when(() => payments.getPriceForFiat(
            wallet: any(named: 'wallet'),
            amount: any(named: 'amount'),
            currency: any(named: 'currency'),
          )).thenThrow(Exception('no rate'));

      final summary = await read();

      expect(summary.priceUnavailable, isFalse);
      expect(summary.usdCost, isNull);
      expect(summary.creditsCost, perItem * BigInt.two);
    });

    test('not free when an item is over Turbo\'s free item size', () async {
      allowance(const TurboFreeAllowance.unlimited());
      when(() => turbo.maxFreeItemSizeBytes).thenReturn(2000);

      final summary = await read();

      expect(summary.isFree, isFalse);
    });

    test('not free after Turbo refused it, whatever the allowance says',
        () async {
      allowance(const TurboFreeAllowance.unlimited());

      final summary = await read(refused: true);

      expect(summary.isFree, isFalse);
      expect(summary.overFreeAllowance, isTrue);
    });

    test('names the wallets whose shared credits it counted', () async {
      allowance(const TurboFreeAllowance.disabled());
      balance(_credit, paidBy: ['sharer-a', 'sharer-b']);

      final cost = await reader.read(
        itemSizes: const [2000],
        wallet: wallet,
        walletBalance: BigInt.zero,
      );

      expect(cost.summary.isCovered, isTrue);
      expect(cost.paidBy, ['sharer-a', 'sharer-b']);
      expect(cost.headers, {'x-paid-by': 'sharer-a, sharer-b'});
    });

    test('no shared credits, no header', () async {
      allowance(const TurboFreeAllowance.disabled());

      final cost = await reader.read(
        itemSizes: const [2000],
        wallet: wallet,
        walletBalance: BigInt.zero,
      );

      expect(cost.headers, isEmpty);
    });

    test('never the wallet', () async {
      allowance(const TurboFreeAllowance.disabled());
      balance(BigInt.zero);

      final summary = (await reader.read(
        itemSizes: const [2000],
        wallet: wallet,
        walletBalance: BigInt.from(10).pow(15),
      ))
          .summary;

      expect(summary.method, UploadMethod.turbo);
      expect(summary.offersPaymentChoice, isFalse);
      expect(summary.needsCredits, isTrue);
      verifyNever(() => arweave.getPrice(byteSize: any(named: 'byteSize')));
    });
  });

  group('with Turbo uploads off', () {
    setUp(() => when(() => turbo.useTurboUpload).thenReturn(false));

    test('priced in AR for the bundle, paid from the wallet', () async {
      when(() => arweave.getPrice(byteSize: any(named: 'byteSize')))
          .thenAnswer((_) async => BigInt.from(1000));

      final summary = (await reader.read(
        itemSizes: const [1800, 2100],
        wallet: wallet,
        walletBalance: BigInt.from(1000),
      ))
          .summary;

      verify(() => arweave.getPrice(byteSize: 32 + 64 * 2 + 3900)).called(1);
      expect(summary.method, UploadMethod.ar);
      expect(summary.arCost, BigInt.from(1000));
      expect(summary.isCovered, isTrue);
      verifyNever(
          () => payments.getFreeAllowance(wallet: any(named: 'wallet')));
    });

    test('not covered when the wallet is short', () async {
      when(() => arweave.getPrice(byteSize: any(named: 'byteSize')))
          .thenAnswer((_) async => BigInt.from(1000));

      final summary = (await reader.read(
        itemSizes: const [1800],
        wallet: wallet,
        walletBalance: BigInt.from(999),
      ))
          .summary;

      expect(summary.isCovered, isFalse);
      expect(summary.needsCredits, isFalse);
    });

    test('no price when the gateway will not give one', () async {
      when(() => arweave.getPrice(byteSize: any(named: 'byteSize')))
          .thenThrow(Exception('down'));

      final summary = (await reader.read(
        itemSizes: const [1800],
        wallet: wallet,
        walletBalance: BigInt.from(10).pow(15),
      ))
          .summary;

      expect(summary.priceUnavailable, isTrue);
      expect(summary.isCovered, isFalse);
    });
  });

  test('an unsigned item measures what it weighs once signed', () async {
    final item = DataItem.withBlobData(data: Uint8List.fromList([1, 2, 3]))
      ..setOwner(await wallet.getOwner())
      ..addTag('App-Name', 'ArDrive-App')
      ..addTag('License', 'yRj4a5KMctX_uOmKWCFJIjmY8DeJcusVk6-HzLiM_t8');

    final measured = signedDataItemSize(item);
    await item.sign(ArweaveSigner(wallet));

    expect(measured, (await item.asBinary()).length);
  });
}
