import 'dart:async';
import 'dart:convert';

import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:ardrive/utils/key_value_store.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockArioSDK extends Mock implements ArioSDK {}

class FakeKeyValueStore implements KeyValueStore {
  final Map<String, Object> _values = {};

  @override
  FutureOr<bool?> getBool(String key) => _values[key] as bool?;

  @override
  FutureOr<String?> getString(String key) => _values[key] as String?;

  @override
  FutureOr<Set<String>> getKeys() => _values.keys.toSet();

  @override
  Future<bool> putBool(String key, bool value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> putString(String key, String value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _values.remove(key);
    return true;
  }
}

Gateway _makeGateway(String fqdn) {
  return Gateway(
    operatorStake: 1000,
    gatewayAddress: 'gateway-address-$fqdn',
    observerAddress: 'observer-address-$fqdn',
    settings: Settings(
      port: 443,
      protocol: 'https',
      allowDelegatedStaking: true,
      fqdn: fqdn,
      delegateRewardShareRatio: 10,
      properties: '',
      note: '',
      minDelegatedStake: 100,
      label: 'Gateway $fqdn',
      autoStake: true,
    ),
    startTimestamp: 0,
    totalDelegatedStake: 0,
    stats: Stats(
      failedConsecutiveEpochs: 0,
      observedEpochCount: 1,
      passedConsecutiveEpochs: 1,
      totalEpochCount: 1,
      prescribedEpochCount: 1,
      passedEpochCount: 1,
      failedEpochCount: 0,
    ),
    status: 'joined',
  );
}

void main() {
  const cacheKey = 'gar_gateways_cache_v1';

  late MockArioSDK sdk;
  late FakeKeyValueStore store;
  late DataGatewayFallback fallback;

  setUp(() {
    sdk = MockArioSDK();
    store = FakeKeyValueStore();
    fallback = DataGatewayFallback(arioSDK: sdk, store: store);
  });

  group('DataGatewayFallback.getGatewaysCached', () {
    test('serves the persisted list without calling the SDK', () async {
      final persisted = [_makeGateway('persisted.gateway.com')];
      await store.putString(
        cacheKey,
        json.encode(persisted.map((g) => g.toJson()).toList()),
      );

      final result = await fallback.getGatewaysCached();

      expect(result, hasLength(1));
      expect(result.first.settings.fqdn, 'persisted.gateway.com');
      verifyNever(() => sdk.getGateways());
    });

    test('fetches from the SDK once and persists when nothing is stored',
        () async {
      final fetched = [_makeGateway('fetched.gateway.com')];
      when(() => sdk.getGateways()).thenAnswer((_) async => fetched);

      final first = await fallback.getGatewaysCached();
      final second = await fallback.getGatewaysCached();

      expect(first, equals(fetched));
      expect(second, equals(fetched));
      verify(() => sdk.getGateways()).called(1);

      final raw = await store.getString(cacheKey);
      expect(raw, isNotNull, reason: 'fetched list must be persisted');
      final roundTripped = (json.decode(raw!) as List)
          .map((e) => Gateway.fromJson(e as Map<String, dynamic>))
          .toList();
      expect(roundTripped.single.settings.fqdn, 'fetched.gateway.com');
    });

    test('a fresh instance reads the persisted list instead of refetching',
        () async {
      final fetched = [_makeGateway('fetched.gateway.com')];
      when(() => sdk.getGateways()).thenAnswer((_) async => fetched);
      await fallback.getGatewaysCached();

      // Simulate a new app session sharing the same storage.
      final newSdk = MockArioSDK();
      final newSession = DataGatewayFallback(arioSDK: newSdk, store: store);

      final result = await newSession.getGatewaysCached();

      expect(result.single.settings.fqdn, 'fetched.gateway.com');
      verifyNever(() => newSdk.getGateways());
    });

    test('caches an empty list on SDK failure and does not retry or persist',
        () async {
      when(() => sdk.getGateways()).thenThrow(Exception('rpc down'));

      final first = await fallback.getGatewaysCached();
      final second = await fallback.getGatewaysCached();

      expect(first, isEmpty);
      expect(second, isEmpty);
      verify(() => sdk.getGateways()).called(1);
      expect(store.getString(cacheKey), isNull,
          reason: 'failures must not be persisted');
    });

    test('recovers from a corrupt persisted entry by refetching', () async {
      await store.putString(cacheKey, 'not-json');
      final fetched = [_makeGateway('fetched.gateway.com')];
      when(() => sdk.getGateways()).thenAnswer((_) async => fetched);

      final result = await fallback.getGatewaysCached();

      expect(result.single.settings.fqdn, 'fetched.gateway.com');
      verify(() => sdk.getGateways()).called(1);
    });
  });

  group('DataGatewayFallback.refreshGateways', () {
    test('always hits the SDK and replaces the persisted list', () async {
      final original = [_makeGateway('old.gateway.com')];
      await store.putString(
        cacheKey,
        json.encode(original.map((g) => g.toJson()).toList()),
      );
      await fallback.getGatewaysCached();

      final refreshed = [_makeGateway('new.gateway.com')];
      when(() => sdk.getGateways()).thenAnswer((_) async => refreshed);

      final result = await fallback.refreshGateways();

      expect(result.single.settings.fqdn, 'new.gateway.com');
      verify(() => sdk.getGateways()).called(1);

      final raw = await store.getString(cacheKey);
      final roundTripped = (json.decode(raw!) as List)
          .map((e) => Gateway.fromJson(e as Map<String, dynamic>))
          .toList();
      expect(roundTripped.single.settings.fqdn, 'new.gateway.com');

      // Subsequent cached reads serve the refreshed list.
      final cached = await fallback.getGatewaysCached();
      expect(cached.single.settings.fqdn, 'new.gateway.com');
      verifyNoMoreInteractions(sdk);
    });
  });
}
