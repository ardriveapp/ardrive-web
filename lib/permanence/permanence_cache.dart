import 'dart:async';
import 'dart:convert';

import 'package:ardrive/permanence/ar_spend.dart';
import 'package:ardrive/permanence/permanence_panel.dart';
import 'package:ardrive/utils/key_value_store.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive/utils/logger.dart';

/// How long the network's price for a size is reused.
const permanencePriceTtl = Duration(minutes: 10);

/// How long AR's dollar price is reused.
const permanenceRateTtl = Duration(minutes: 10);

/// How long the Turbo credits a wallet has used are reused, once read.
const permanenceSpendTtl = Duration(minutes: 30);

/// How long a count of the AR a wallet paid directly is reused, once the
/// network has been asked.
const permanenceArTallyTtl = Duration(minutes: 30);

/// Where the Turbo credits used are kept between visits. Credit amounts
/// only: nothing here can sign or spend.
const permanenceSpendStoragePrefix = 'permanenceSpend_v1_';

/// How long after this app spends that a count of AR is re-checked soon,
/// because a transaction it posted a moment ago is not yet mined and indexed.
const permanenceArRecentSpendWindow = Duration(minutes: 10);

/// The re-check limit for a count made within that window.
const permanenceArRecentTtl = Duration(minutes: 1);

/// Whether something read at [at] is still current at [now] under [ttl]. A
/// clock that moved backward makes the age negative: not current.
bool _within(DateTime now, DateTime at, Duration ttl) {
  final age = now.difference(at);

  return age >= Duration.zero && age < ttl;
}

/// The Turbo credits a wallet has used, and when they were read.
class SpendEntry {
  const SpendEntry({
    required this.lookup,
    required this.fetchedAt,
    this.invalidated = false,
  });

  final SpendLookup lookup;
  final DateTime fetchedAt;

  /// Something this app did, since [fetchedAt], that changes the figure.
  final bool invalidated;

  bool isFresh(DateTime now) =>
      !invalidated && _within(now, fetchedAt, permanenceSpendTtl);

  SpendEntry asInvalidated() => SpendEntry(
        lookup: lookup,
        fetchedAt: fetchedAt,
        invalidated: true,
      );

  String toJson() => jsonEncode({
        'kind': lookup.tooMany
            ? 'tooMany'
            : lookup.creditsWinc != null
                ? 'found'
                : 'none',
        'winc': lookup.creditsWinc?.toString(),
        'at': fetchedAt.millisecondsSinceEpoch,
        'invalidated': invalidated,
      });

  static SpendEntry? fromJson(String? source) {
    if (source == null) {
      return null;
    }

    try {
      final json = jsonDecode(source) as Map<String, dynamic>;
      final winc = json['winc'] as String?;
      final SpendLookup lookup;

      switch (json['kind']) {
        case 'tooMany':
          lookup = const SpendLookup.tooMany();
        case 'found':
          lookup = SpendLookup.found(BigInt.parse(winc!));
        case 'none':
          lookup = const SpendLookup.none();
        default:
          return null;
      }

      return SpendEntry(
        lookup: lookup,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(json['at'] as int),
        invalidated: json['invalidated'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// What the panel does with the Turbo credits used when it opens.
class SpendPlan {
  const SpendPlan({this.spend, this.loadSpend, this.shown});

  /// Credits being read now, or already read and still current.
  final Future<SpendLookup>? spend;

  /// Reads them when the reader asks. Set instead of [spend] for a wallet
  /// that would ask its owner to sign.
  final Future<SpendLookup> Function()? loadSpend;

  /// An earlier reading to show until [spend] arrives, or beside the
  /// request to read again. Null when the reading is current, or when there
  /// is none.
  final SpendEntry? shown;
}

class _ArEntry {
  const _ArEntry(
    this.tally,
    this.checkedAt, {
    this.checked = true,
    this.ttl = permanenceArTallyTtl,
  });

  final ArSpendTally tally;
  final DateTime checkedAt;

  /// How long the count is reused.
  final Duration ttl;

  /// Whether the network answered the last time it was asked, and the count
  /// is not a lower bound.
  final bool checked;
}

/// What the permanence panel last read, so that opening it again does not
/// ask again.
///
/// - The network's price for a size and AR's dollar price are kept for ten
///   minutes. The price is keyed by the exact size, so a size that changed
///   asks again.
/// - The Turbo credits a wallet has used and the count of AR it paid directly
///   are kept for thirty minutes. Anything this app does that spends
///   ([spendChanged]) makes both stale at once. Changes made elsewhere, such
///   as an upload from another device, show up when the time runs out.
/// - The credits used are also kept in local storage, so the panel can show
///   them at once on the next visit. [clear] removes them at logout.
class PermanenceCache {
  PermanenceCache({
    DateTime Function()? now,
    Future<KeyValueStore> Function()? openStore,
  })  : _now = now ?? DateTime.now,
        _openStore = openStore ?? LocalKeyValueStore.getInstance;

  /// The one the app uses. Uploads, payments and logout reach it from places
  /// that have no way to be handed one.
  static final PermanenceCache shared = PermanenceCache();

  final DateTime Function() _now;
  final Future<KeyValueStore> Function() _openStore;

  /// Bumped whenever something changes the figures, so a read that began
  /// before the change is not taken for one that began after it.
  int _generation = 0;

  /// Bumped by [clear]: a read that began before it belongs to a wallet that
  /// has signed out, and is kept nowhere.
  int _epoch = 0;

  final _prices = <int, (BigInt, DateTime)>{};
  (double, DateTime)? _rate;
  final _spend = <String, SpendEntry>{};
  final _spendReads = <String, (int, Future<SpendLookup>)>{};
  final _arTallies = <String, _ArEntry>{};
  final _arCounts = <String, (int, Future<ArSpendTally>)>{};

  /// When this app last spent, for the AR count's shorter limit.
  DateTime? _lastSpendAt;

  // The network's price.

  /// What the network charges today for [bytes], with AR's dollar price.
  /// Asks for whichever of the two it does not already hold, together.
  /// Null when the price itself could not be read; a rate that could not be
  /// read leaves the price in AR alone, and is asked again next time.
  Future<NetworkCost?> costToday({
    required int bytes,
    required Future<BigInt> Function() price,
    required Future<double?> Function() usdPerAr,
  }) async {
    final now = _now();
    final cachedPrice = _prices[bytes];
    final cachedRate = _rate;

    final priceFresh =
        cachedPrice != null && _within(now, cachedPrice.$2, permanencePriceTtl);
    final rateFresh =
        cachedRate != null && _within(now, cachedRate.$2, permanenceRateTtl);

    // Started together, as the panel always did.
    final pricing = priceFresh ? null : price();
    final rating = rateFresh ? null : usdPerAr();

    final BigInt winston;

    if (pricing == null) {
      winston = cachedPrice!.$1;
    } else {
      try {
        winston = await pricing;
      } catch (e) {
        logger
            .w('Could not read the network price for the permanence panel: $e');
        // Do not leave a rate request without anyone waiting on it.
        unawaited(rating?.catchError((_) => null));
        return null;
      }

      _prices.removeWhere(
        (_, entry) => !_within(now, entry.$2, permanencePriceTtl),
      );
      _prices[bytes] = (winston, now);
    }

    double? rate;

    if (rating == null) {
      rate = cachedRate!.$1;
    } else {
      rate = await rating;

      if (rate != null) {
        _rate = (rate, now);
      }
    }

    return NetworkCost(winston: winston, usdPerAr: rate);
  }

  // The Turbo credits used.

  String _spendKey(String owner) => '$permanenceSpendStoragePrefix$owner';

  Future<SpendEntry?> _spendEntry(String owner) async {
    final held = _spend[owner];

    if (held != null) {
      return held;
    }

    try {
      final store = await _openStore();
      final stored =
          SpendEntry.fromJson(await store.getString(_spendKey(owner)));

      if (stored != null) {
        return _spend[owner] ??= stored;
      }
    } catch (e) {
      logger.w('Could not read the stored Turbo credits used: $e');
    }

    return null;
  }

  /// What to do with the Turbo credits used as the panel opens for [owner].
  ///
  /// - A reading still current is used as it is: nothing is asked.
  /// - An older one is shown while [fetch] reads again, for a wallet that
  ///   [signsSilently]. A wallet that would ask its owner to sign is never
  ///   asked here: the older reading is shown, with a way to read again.
  /// - With no reading at all, nothing is shown and [fetch] runs (or waits to
  ///   be asked), as before.
  Future<SpendPlan> planSpend({
    required String owner,
    required bool signsSilently,
    required Future<SpendLookup> Function() fetch,
  }) async {
    final entry = await _spendEntry(owner);

    if (entry != null && entry.isFresh(_now())) {
      return SpendPlan(spend: Future.value(entry.lookup));
    }

    Future<SpendLookup> read() => _readSpend(owner, fetch);

    return signsSilently
        ? SpendPlan(spend: read(), shown: entry)
        : SpendPlan(loadSpend: read, shown: entry);
  }

  Future<SpendLookup> _readSpend(
    String owner,
    Future<SpendLookup> Function() fetch,
  ) {
    // A read that began before the app last spent might not include it: it
    // is not joined.
    final running = _spendReads[owner];

    if (running != null && running.$1 == _generation) {
      return running.$2;
    }

    final generation = _generation;
    final epoch = _epoch;

    final read = () async {
      try {
        final lookup = await fetch();

        // A failed read says nothing about the credits, so it replaces
        // nothing.
        if (!lookup.failed && epoch == _epoch) {
          final entry = SpendEntry(
            lookup: lookup,
            fetchedAt: _now(),
            // The app spent while this was being read: it might not count it.
            invalidated: generation != _generation,
          );

          _spend[owner] = entry;
          await _storeSpend(owner, entry, epoch);
        }

        return lookup;
      } finally {
        if (_spendReads[owner]?.$1 == generation && epoch == _epoch) {
          _spendReads.remove(owner);
        }
      }
    }();

    _spendReads[owner] = (generation, read);

    return read;
  }

  Future<void> _storeSpend(String owner, SpendEntry entry, int epoch) async {
    try {
      final store = await _openStore();

      // Signed out while the store was opening: nothing is kept.
      if (epoch != _epoch) {
        return;
      }

      await store.putString(_spendKey(owner), entry.toJson());
    } catch (e) {
      logger.w('Could not keep the Turbo credits used: $e');
    }
  }

  // The AR paid directly.

  /// The count of AR [owner] paid directly. Used as it stands while the
  /// network was asked less than thirty minutes ago and nothing has spent
  /// since; otherwise [count] asks again, and carries on where an earlier
  /// count stopped.
  Future<ArSpendTally> arSpend({
    required String owner,
    required Future<ArSpendTally> Function(void Function() onFailure) count,
  }) {
    final held = _arTallies[owner];

    if (held != null &&
        held.checked &&
        held.tally.complete &&
        _within(_now(), held.checkedAt, held.ttl)) {
      return Future.value(held.tally);
    }

    final running = _arCounts[owner];

    if (running != null && running.$1 == _generation) {
      return running.$2;
    }

    final generation = _generation;
    final epoch = _epoch;
    var failed = false;

    final counting = () async {
      try {
        final tally = await count(() => failed = true);

        if (epoch == _epoch) {
          final now = _now();
          final spentLately = _lastSpendAt != null &&
              _within(now, _lastSpendAt!, permanenceArRecentSpendWindow);

          _arTallies[owner] = _ArEntry(
            tally,
            now,
            // Not a figure to reuse: the network did not answer, or the app
            // spent while it was counting.
            checked: !failed && generation == _generation,
            // A transaction posted a moment ago is not mined yet, so soon after
            // spending the count is checked again sooner.
            ttl: spentLately ? permanenceArRecentTtl : permanenceArTallyTtl,
          );
        }

        return tally;
      } finally {
        if (_arCounts[owner]?.$1 == generation && epoch == _epoch) {
          _arCounts.remove(owner);
        }
      }
    }();

    _arCounts[owner] = (generation, counting);

    return counting;
  }

  // What changes them.

  /// Something this app did has spent, or added, Turbo credits or AR: an
  /// upload finished, a top-up went through. The credits used and the count
  /// of AR paid are read again the next time the panel opens; the older
  /// figures stay on screen until then. The network's price does not depend
  /// on it.
  void spendChanged() {
    _generation++;
    _lastSpendAt = _now();

    _spend.updateAll((_, entry) => entry.asInvalidated());
    _arTallies.updateAll(
      (_, entry) => _ArEntry(
        entry.tally,
        entry.checkedAt,
        checked: false,
        ttl: entry.ttl,
      ),
    );

    unawaited(_invalidateStored());
  }

  Future<void> _invalidateStored() async {
    final epoch = _epoch;

    try {
      final store = await _openStore();

      for (final key in await store.getKeys()) {
        // Signed out meanwhile: clear() has removed, or is removing, these.
        if (epoch != _epoch) {
          return;
        }

        if (!key.startsWith(permanenceSpendStoragePrefix)) {
          continue;
        }

        final entry = SpendEntry.fromJson(await store.getString(key));

        if (entry != null && !entry.invalidated && epoch == _epoch) {
          await store.putString(key, entry.asInvalidated().toJson());
        }
      }
    } catch (e) {
      logger.w('Could not mark the stored Turbo credits used as stale: $e');
    }
  }

  /// Forgets everything, in memory and in local storage: the next wallet to
  /// sign in must not see this one's figures.
  Future<void> clear() async {
    _generation++;
    _epoch++;
    _prices.clear();
    _rate = null;
    _spend.clear();
    _spendReads.clear();
    _arTallies.clear();
    _arCounts.clear();
    _lastSpendAt = null;

    try {
      final store = await _openStore();

      for (final key in await store.getKeys()) {
        if (key.startsWith(permanenceSpendStoragePrefix)) {
          await store.remove(key);
        }
      }
    } catch (e) {
      logger.w('Could not clear the stored Turbo credits used: $e');
    }
  }
}

/// [tallyArSpend], telling [onFailure] when the network could not be asked.
/// The count itself carries on with what it had when a request fails, which
/// is right to show and wrong to keep for half an hour.
Future<ArSpendTally> countArSpend({
  required void Function() onFailure,
  required String storageKey,
  required String? Function(String key) read,
  required Future<void> Function(String key, String value) write,
  required Future<ArFeePage> Function({required int minHeight, String? after})
      fetchPage,
  KnownTxLookup? knownAmong,
}) =>
    tallyArSpend(
      storageKey: storageKey,
      read: read,
      write: write,
      knownAmong: knownAmong,
      fetchPage: ({required minHeight, after}) async {
        try {
          return await fetchPage(minHeight: minHeight, after: after);
        } catch (_) {
          onFailure();
          rethrow;
        }
      },
    );
