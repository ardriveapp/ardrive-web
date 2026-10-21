import 'dart:typed_data';

import 'package:ardrive/permanence/permanence_cache.dart';
import 'package:ardrive/permanence/permanence_panel.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_utils/utils.dart';

class _MockArDriveHTTP extends Mock implements ArDriveHTTP {}

void main() {
  const configFallback = 100000; // stale config value (97.66 KiB)

  late _MockArDriveHTTP httpClient;

  setUpAll(() {
    registerFallbackValue(const Stream<List<int>>.empty());
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    httpClient = _MockArDriveHTTP();
  });

  TurboUploadService makeService() => TurboUploadService(
        turboUploadUri: Uri.parse('https://turbo.example'),
        allowedDataItemSize: configFallback,
        httpClient: httpClient,
      );

  void stubInfo(dynamic body) {
    when(() => httpClient.get(url: any(named: 'url'))).thenAnswer(
      (_) async =>
          ArDriveHTTPResponse(data: body, statusCode: 200, retryAttempts: 0),
    );
  }

  group('refreshMaxItemBytes', () {
    test(
        'reads the real /v1/info shape (freeTier.maxItemBytes) — the bug fix: '
        '105 KiB, not the stale 100000 config fallback', () async {
      // The actual production/staging /v1/info payload: no top-level
      // maxItemBytes; the per-item cap is nested under freeTier.
      stubInfo(
        '{"version":"0.2.0","freeUploadLimitBytes":107520,'
        '"freeTier":{"lifetimeBytes":10485760,"ipBytes":10485760,'
        '"maxItemBytes":107520}}',
      );
      final service = makeService();
      await service.refreshMaxItemBytes();
      expect(service.maxFreeItemSizeBytes, 107520);
    });

    test('falls back to top-level freeUploadLimitBytes when freeTier is absent',
        () async {
      stubInfo('{"freeUploadLimitBytes":107520}');
      final service = makeService();
      await service.refreshMaxItemBytes();
      expect(service.maxFreeItemSizeBytes, 107520);
    });

    test('still honours a top-level maxItemBytes if a deployment returns one',
        () async {
      stubInfo('{"maxItemBytes":123456}');
      final service = makeService();
      await service.refreshMaxItemBytes();
      expect(service.maxFreeItemSizeBytes, 123456);
    });

    test('accepts an already-decoded Map (not just a JSON string)', () async {
      stubInfo({
        'freeTier': {'maxItemBytes': 107520}
      });
      final service = makeService();
      await service.refreshMaxItemBytes();
      expect(service.maxFreeItemSizeBytes, 107520);
    });

    test('keeps the config fallback when the payload has no cap', () async {
      stubInfo('{"version":"0.2.0"}');
      final service = makeService();
      await service.refreshMaxItemBytes();
      expect(service.maxFreeItemSizeBytes, configFallback);
    });

    test('keeps the config fallback on a fetch error (fails safe)', () async {
      when(() => httpClient.get(url: any(named: 'url')))
          .thenThrow(Exception('network down'));
      final service = makeService();
      await service.refreshMaxItemBytes();
      expect(service.maxFreeItemSizeBytes, configFallback);
    });

    test('ignores a non-positive cap', () async {
      stubInfo('{"freeTier":{"maxItemBytes":0}}');
      final service = makeService();
      await service.refreshMaxItemBytes();
      expect(service.maxFreeItemSizeBytes, configFallback);
    });

    test('an unusable preferred value does not mask a good fallback beside it',
        () async {
      // The candidates used to be chosen with `??` and validated afterwards,
      // so any non-null preferred value won - even a useless one - and the
      // valid number next to it was never looked at.
      stubInfo(
        '{"freeTier":{"maxItemBytes":"oops"},"freeUploadLimitBytes":107520}',
      );
      final service = makeService();
      await service.refreshMaxItemBytes();
      expect(service.maxFreeItemSizeBytes, 107520);
    });

    test('a negative preferred value does not mask a good fallback', () async {
      stubInfo(
        '{"freeTier":{"maxItemBytes":-1},"freeUploadLimitBytes":107520}',
      );
      final service = makeService();
      await service.refreshMaxItemBytes();
      expect(service.maxFreeItemSizeBytes, 107520);
    });

    test('rejects a fractional cap rather than truncating it to zero',
        () async {
      // The dangerous shape: 0.5 is `> 0`, so it passed, and `toInt()` made it
      // 0 - a cap of zero bytes, which is not the fallback. Nothing would have
      // qualified for a free upload.
      stubInfo('{"freeTier":{"maxItemBytes":0.5}}');
      final service = makeService();
      await service.refreshMaxItemBytes();
      expect(service.maxFreeItemSizeBytes, configFallback);
    });

    test('rejects a fractional cap even when it is large', () async {
      stubInfo('{"freeTier":{"maxItemBytes":107520.5}}');
      final service = makeService();
      await service.refreshMaxItemBytes();
      expect(service.maxFreeItemSizeBytes, configFallback);
    });

    test('accepts a whole number expressed as a double', () async {
      // JSON has one number type; a server may well send 107520.0.
      stubInfo({
        'freeTier': {'maxItemBytes': 107520.0}
      });
      final service = makeService();
      await service.refreshMaxItemBytes();
      expect(service.maxFreeItemSizeBytes, 107520);
    });

    test('keeps the last good cap when a later refresh fails', () async {
      // Deliberate: reverting to the configured value on a transient failure
      // would reintroduce the stale cap this fix exists to remove. A cap the
      // server actually reported is better information than the config, and it
      // does not go stale between two calls seconds apart.
      stubInfo('{"freeTier":{"maxItemBytes":107520}}');
      final service = makeService();
      await service.refreshMaxItemBytes();
      expect(service.maxFreeItemSizeBytes, 107520);

      when(() => httpClient.get(url: any(named: 'url')))
          .thenThrow(Exception('network down'));
      await service.refreshMaxItemBytes();
      expect(service.maxFreeItemSizeBytes, 107520);
    });

    test('keeps the last good cap when a later payload is unusable', () async {
      stubInfo('{"freeTier":{"maxItemBytes":107520}}');
      final service = makeService();
      await service.refreshMaxItemBytes();

      stubInfo('{"version":"0.2.0"}');
      await service.refreshMaxItemBytes();
      expect(service.maxFreeItemSizeBytes, 107520);
    });
  });

  group('postDataItem and the permanence panel', () {
    Future<SpendEntry?> shown() async =>
        (await PermanenceCache.shared.planSpend(
          owner: 'wallet-a',
          signsSilently: true,
          fetch: () async => SpendLookup.found(BigInt.one),
        ))
            .shown;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await PermanenceCache.shared.clear();
      // The panel has read the credits used.
      final read = await PermanenceCache.shared.planSpend(
        owner: 'wallet-a',
        signsSilently: true,
        fetch: () async => SpendLookup.found(BigInt.one),
      );
      await read.spend;
    });

    Future<DataItem> dataItem(Wallet wallet) async {
      final item = DataItem.withBlobData(
        owner: await wallet.getOwner(),
        data: Uint8List(8),
      );
      await item.sign(ArweaveSigner(wallet));
      return item;
    }

    test('makes the credits used be read again once the item is accepted',
        () async {
      when(
        () => httpClient.postBytesAsStream(
          url: any(named: 'url'),
          data: any(named: 'data'),
          onSendProgress: any(named: 'onSendProgress'),
          headers: any(named: 'headers'),
          receiveTimeout: any(named: 'receiveTimeout'),
          sendTimeout: any(named: 'sendTimeout'),
        ),
      ).thenAnswer(
        (_) async =>
            ArDriveHTTPResponse(data: '', statusCode: 200, retryAttempts: 0),
      );

      final wallet = getTestWallet();

      await makeService().postDataItem(
        dataItem: await dataItem(wallet),
        wallet: wallet,
      );

      expect((await shown())!.invalidated, isTrue);
    });
  });
}
