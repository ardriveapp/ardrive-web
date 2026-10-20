import 'dart:async';

import 'package:ardrive/permanence/ar_spend.dart';
import 'package:ardrive/permanence/permanence_cache.dart';
import 'package:ardrive/permanence/permanence_panel.dart';
import 'package:ardrive/utils/key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<bool> putString(String key, String value) async {
    values[key] = value;
    return true;
  }

  @override
  String? getString(String key) => values[key];

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Set<String> getKeys() => values.keys.toSet();

  @override
  Future<bool> putBool(String key, bool value) async => true;

  @override
  bool? getBool(String key) => null;
}

void main() {
  late DateTime now;
  late _MemoryStore store;
  late PermanenceCache cache;

  PermanenceCache newCache() =>
      PermanenceCache(now: () => now, openStore: () async => store);

  final winston = BigInt.from(10).pow(12);

  setUp(() {
    now = DateTime(2026, 10, 20, 12);
    store = _MemoryStore();
    cache = newCache();
  });

  void later(Duration by) => now = now.add(by);

  /// Counts the calls made to each of the things the panel asks for.
  late int priceCalls;
  late int rateCalls;
  late int spendCalls;
  late int tallyCalls;

  setUp(() {
    priceCalls = 0;
    rateCalls = 0;
    spendCalls = 0;
    tallyCalls = 0;
  });

  Future<NetworkCost?> cost(PermanenceCache c, {int bytes = 1000}) =>
      c.costToday(
        bytes: bytes,
        price: () async {
          priceCalls++;
          return winston * BigInt.from(bytes);
        },
        usdPerAr: () async {
          rateCalls++;
          return 5.0;
        },
      );

  Future<SpendLookup> fetchSpend() async {
    spendCalls++;
    return SpendLookup.found(winston * BigInt.from(spendCalls));
  }

  Future<SpendPlan> plan(
    PermanenceCache c, {
    String owner = 'wallet-a',
    bool silent = true,
  }) =>
      c.planSpend(owner: owner, signsSilently: silent, fetch: fetchSpend);

  Future<ArSpendTally> tally(PermanenceCache c, {String owner = 'wallet-a'}) =>
      c.arSpend(
        owner: owner,
        count: (onFailure) async {
          tallyCalls++;
          return ArSpendTally(
            winston: winston,
            uploads: 1,
            lastHeight: 10,
          );
        },
      );

  /// Opens the panel as the profile card does.
  Future<void> open(PermanenceCache c, {int bytes = 1000}) async {
    await cost(c, bytes: bytes);
    await (await plan(c)).spend;
    await tally(c);
  }

  group('opening twice within the time limits', () {
    test('asks for each figure once', () async {
      await open(cache);
      later(const Duration(minutes: 5));
      await open(cache);

      expect(priceCalls, 1);
      expect(rateCalls, 1);
      expect(spendCalls, 1);
      expect(tallyCalls, 1);
    });

    test('gives back the same figures', () async {
      final first = await cost(cache);
      later(const Duration(minutes: 5));
      final second = await cost(cache);

      expect(second!.winston, first!.winston);
      expect(second.usdPerAr, 5);

      await (await plan(cache)).spend;
      later(const Duration(minutes: 5));
      final reopened = await plan(cache);

      expect((await reopened.spend)!.creditsWinc, winston);
      expect(reopened.shown, isNull);
    });
  });

  group('after the time limits', () {
    test('asks for the price and the rate again after ten minutes', () async {
      await cost(cache);
      later(const Duration(minutes: 9));
      await cost(cache);
      expect(priceCalls, 1);

      later(const Duration(minutes: 2));
      await cost(cache);
      expect(priceCalls, 2);
      expect(rateCalls, 2);
    });

    test('reads the credits and counts the AR again after thirty minutes',
        () async {
      await open(cache);
      later(const Duration(minutes: 29));
      await open(cache);
      expect(spendCalls, 1);
      expect(tallyCalls, 1);

      later(const Duration(minutes: 2));
      final reopened = await plan(cache);
      await reopened.spend;
      await tally(cache);

      expect(spendCalls, 2);
      expect(tallyCalls, 2);
      // The older reading is there to show while the new one arrives.
      expect(reopened.shown!.lookup.creditsWinc, winston);
    });
  });

  group('something this app spends', () {
    test('makes the credits and the AR count be read again', () async {
      await open(cache);
      cache.spendChanged();
      await open(cache);

      expect(spendCalls, 2);
      expect(tallyCalls, 2);
    });

    test('leaves the price and the rate alone', () async {
      await open(cache);
      cache.spendChanged();
      await open(cache);

      expect(priceCalls, 1);
      expect(rateCalls, 1);
    });

    test('keeps the older credits to show until the new ones arrive', () async {
      await (await plan(cache)).spend;
      cache.spendChanged();

      final reopened = await plan(cache);

      expect(reopened.shown!.lookup.creditsWinc, winston);
      expect(reopened.shown!.invalidated, isTrue);
    });

    test('is not forgotten by a read that began before it', () async {
      final answer = Completer<SpendLookup>();
      final reading = cache
          .planSpend(
            owner: 'wallet-a',
            signsSilently: true,
            fetch: () => answer.future,
          )
          .then((p) => p.spend!);
      await Future<void>.delayed(Duration.zero);

      // The request is in flight when an upload finishes.
      cache.spendChanged();
      answer.complete(SpendLookup.found(winston));
      await reading;

      await (await plan(cache)).spend;
      expect(spendCalls, 1);
    });

    test('is not forgotten by a count that began before it', () async {
      final counting = tally(cache);
      cache.spendChanged();
      await counting;

      await tally(cache);
      expect(tallyCalls, 2);
    });

    test('is remembered after a restart', () async {
      await (await plan(cache)).spend;
      cache.spendChanged();
      // Let the stored copy be marked.
      await Future<void>.delayed(Duration.zero);

      final restarted = newCache();
      final reopened = await plan(restarted);
      await reopened.spend;

      expect(spendCalls, 2);
    });
  });

  group('a different size', () {
    test('asks for the price again, and not for the rate', () async {
      await cost(cache, bytes: 1000);
      final other = await cost(cache, bytes: 2000);

      expect(priceCalls, 2);
      expect(rateCalls, 1);
      expect(other!.winston, winston * BigInt.from(2000));
    });

    test('keeps the first size too', () async {
      await cost(cache, bytes: 1000);
      await cost(cache, bytes: 2000);
      await cost(cache, bytes: 1000);

      expect(priceCalls, 2);
    });
  });

  group('what could not be read', () {
    test('is not kept', () async {
      var calls = 0;
      Future<NetworkCost?> failing() => cache.costToday(
            bytes: 1,
            price: () async {
              calls++;
              throw Exception('gateway down');
            },
            usdPerAr: () async => 5,
          );

      expect(await failing(), isNull);
      expect(await failing(), isNull);
      expect(calls, 2);
    });

    test('a rate that failed leaves the price in AR alone, and is asked again',
        () async {
      var rates = 0;
      Future<NetworkCost?> noRate() => cache.costToday(
            bytes: 1,
            price: () async => winston,
            usdPerAr: () async {
              rates++;
              return null;
            },
          );

      expect((await noRate())!.usdPerAr, isNull);
      await noRate();
      expect(rates, 2);
    });

    test('credits that failed leave the earlier ones in place', () async {
      await (await plan(cache)).spend;
      later(const Duration(minutes: 31));

      final reopened = await cache.planSpend(
        owner: 'wallet-a',
        signsSilently: true,
        fetch: () async => const SpendLookup.failed(),
      );
      expect((await reopened.spend)!.failed, isTrue);
      expect(reopened.shown!.lookup.creditsWinc, winston);

      // And the failure was not taken for a reading.
      final again = await plan(cache);
      expect(again.shown!.lookup.creditsWinc, winston);
      expect(spendCalls, 2);
    });

    test('an AR count that could not ask the network is not reused', () async {
      Future<ArSpendTally> failedCount() => cache.arSpend(
            owner: 'wallet-a',
            count: (onFailure) async {
              tallyCalls++;
              onFailure();
              return ArSpendTally.empty;
            },
          );

      await failedCount();
      await failedCount();
      expect(tallyCalls, 2);
    });

    test('countArSpend says so when a page cannot be fetched', () async {
      var failed = 0;

      await countArSpend(
        onFailure: () => failed++,
        storageKey: 'k',
        read: (_) => null,
        write: (_, __) async {},
        fetchPage: ({required minHeight, after}) async =>
            throw Exception('down'),
      );

      expect(failed, 1);
    });

    test('an AR count that stopped short is carried on, not reused', () async {
      Future<ArSpendTally> partial() => cache.arSpend(
            owner: 'wallet-a',
            count: (onFailure) async {
              tallyCalls++;
              return ArSpendTally(
                winston: winston,
                uploads: 1,
                lastHeight: 10,
                cursor: 'more',
              );
            },
          );

      await partial();
      await partial();
      expect(tallyCalls, 2);
    });
  });

  group('kept between visits', () {
    test('the credits used are read back for the same wallet', () async {
      await (await plan(cache)).spend;

      final restarted = newCache();
      final reopened = await plan(restarted);

      expect((await reopened.spend)!.creditsWinc, winston);
      expect(spendCalls, 1);
    });

    test('and for no other wallet', () async {
      await (await plan(cache)).spend;

      final restarted = newCache();
      final other = await plan(restarted, owner: 'wallet-b');
      await other.spend;

      expect(other.shown, isNull);
      expect(spendCalls, 2);
    });

    test('an older reading is shown while a new one is read', () async {
      await (await plan(cache)).spend;
      later(const Duration(hours: 3));

      final restarted = newCache();
      final reopened = await plan(restarted);

      expect(reopened.shown!.lookup.creditsWinc, winston);
      expect(reopened.shown!.fetchedAt, DateTime(2026, 10, 20, 12));
      expect((await reopened.spend)!.creditsWinc, winston * BigInt.two);
    });

    test('holds credit amounts and nothing else', () async {
      await (await plan(cache)).spend;

      expect(store.values.keys, ['${permanenceSpendStoragePrefix}wallet-a']);
      expect(
        store.values.values.single,
        isNot(contains('wallet-a')),
      );
    });

    test('is cleared at logout', () async {
      await open(cache);
      await cache.clear();

      expect(store.values, isEmpty);

      final reopened = await plan(cache);
      await reopened.spend;
      await cost(cache);
      await tally(cache);

      expect(reopened.shown, isNull);
      expect(spendCalls, 2);
      expect(priceCalls, 2);
      expect(tallyCalls, 2);
    });

    test('a stored reading that cannot be understood is ignored', () async {
      store.values['${permanenceSpendStoragePrefix}wallet-a'] = 'not json';

      final reopened = await plan(cache);
      await reopened.spend;

      expect(reopened.shown, isNull);
      expect(spendCalls, 1);
    });

    test('a read that was running at logout is not kept', () async {
      final answer = Completer<SpendLookup>();
      final reading = cache
          .planSpend(
            owner: 'wallet-a',
            signsSilently: true,
            fetch: () => answer.future,
          )
          .then((p) => p.spend!);
      await Future<void>.delayed(Duration.zero);

      await cache.clear();
      answer.complete(SpendLookup.found(winston));
      await reading;

      expect(store.values, isEmpty);
    });
  });

  group('a wallet that asks its owner to sign', () {
    test('is never asked on its own', () async {
      final first = await plan(cache, silent: false);
      expect(first.spend, isNull);
      expect(first.loadSpend, isNotNull);
      expect(spendCalls, 0);

      // Even with an older reading to show.
      await first.loadSpend!();
      later(const Duration(hours: 2));
      final second = await plan(cache, silent: false);

      expect(second.spend, isNull);
      expect(second.loadSpend, isNotNull);
      expect(second.shown!.lookup.creditsWinc, winston);
      expect(spendCalls, 1);
    });

    test('uses a current reading without a signature', () async {
      await (await plan(cache, silent: false)).loadSpend!();
      later(const Duration(minutes: 5));

      final reopened = await plan(cache, silent: false);

      expect((await reopened.spend)!.creditsWinc, winston);
      expect(reopened.loadSpend, isNull);
      expect(spendCalls, 1);
    });

    test('reads when the reader asks', () async {
      await (await plan(cache, silent: false)).loadSpend!();
      later(const Duration(hours: 2));

      final reopened = await plan(cache, silent: false);
      final read = await reopened.loadSpend!();

      expect(read.creditsWinc, winston * BigInt.two);
      expect(spendCalls, 2);
    });
  });
}
