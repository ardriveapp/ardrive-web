import 'dart:convert';

/// One page of a wallet's directly paid ArDrive uploads. See
/// `ArweaveService.getArDriveFeesPage`.
class ArFeePage {
  const ArFeePage({
    required this.winston,
    required this.count,
    required this.lastHeight,
    required this.cursor,
    required this.hasMore,
    this.excluded = const {},
  });

  /// What was paid on this page: fees, and tips. See [arDrivePayment].
  final BigInt winston;

  /// Transactions on this page.
  final int count;

  /// The block height of the page's last transaction, if it had any.
  final int? lastHeight;

  /// Where the next page starts.
  final String? cursor;

  final bool hasMore;

  /// Paid transactions on this page that were not taken for ArDrive's, by
  /// id, with their fees. See [ArSpendTally.excluded].
  final Map<String, BigInt> excluded;
}

/// What a wallet has paid in AR to upload with ArDrive directly, counted so
/// far.
class ArSpendTally {
  const ArSpendTally({
    required this.winston,
    required this.uploads,
    required this.lastHeight,
    this.runMinHeight,
    this.cursor,
    this.runBase,
    this.excluded = const {},
  });

  static final empty = ArSpendTally(
    winston: BigInt.zero,
    uploads: 0,
    lastHeight: -1,
  );

  final BigInt winston;
  final int uploads;

  /// The highest block counted.
  final int lastHeight;

  /// Set while a count is unfinished: the height it started from, and where
  /// it got to. The next count carries on from there rather than starting
  /// again.
  final int? runMinHeight;
  final String? cursor;

  /// What had been counted before the unfinished count began, so it can be
  /// started again cleanly - from its first page, without counting twice -
  /// when its cursor stops working: a gateway switched, a cursor expired.
  final ArSpendTally? runBase;

  /// Paid transactions a count left out because nothing yet said they were
  /// ArDrive's, by id, with their fees.
  ///
  /// The count moves on past them, so without this one left out before its
  /// drive had synced - the data of a direct upload carries no tag that says
  /// whose it is - would never be counted. Each count looks at these again
  /// first, against what sync knows by then. At most [maxExcluded], the most
  /// recent kept.
  final Map<String, BigInt> excluded;

  static const maxExcluded = 5000;

  /// Whether everything up to the last count has been counted. When it is
  /// not, the figure is a lower bound.
  bool get complete => cursor == null;

  /// The amount in AR (a winston is a trillionth of one).
  double get ar => winston / BigInt.from(10).pow(12);

  Map<String, dynamic> toJson() => {
        'winston': winston.toString(),
        'uploads': uploads,
        'lastHeight': lastHeight,
        if (runMinHeight != null) 'runMinHeight': runMinHeight,
        if (cursor != null) 'cursor': cursor,
        if (runBase != null) 'runBase': runBase!.toJson(),
        if (excluded.isNotEmpty)
          'excluded': {
            for (final entry in excluded.entries)
              entry.key: entry.value.toString(),
          },
      };

  static ArSpendTally? fromJson(String? source) {
    if (source == null) {
      return null;
    }

    try {
      return _fromMap(jsonDecode(source) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static ArSpendTally _fromMap(Map<String, dynamic> json) => ArSpendTally(
        winston: BigInt.parse(json['winston'] as String),
        uploads: json['uploads'] as int,
        lastHeight: json['lastHeight'] as int,
        runMinHeight: json['runMinHeight'] as int?,
        cursor: json['cursor'] as String?,
        runBase: json['runBase'] == null
            ? null
            : _fromMap(json['runBase'] as Map<String, dynamic>),
        excluded: {
          for (final entry
              in ((json['excluded'] as Map<String, dynamic>?) ?? {}).entries)
            entry.key: BigInt.parse(entry.value as String),
        },
      );

  /// Everything this tally, and the count it carries on from, left out.
  Set<String> get excludedIds => {
        ...excluded.keys,
        ...?runBase?.excludedIds,
      };

  /// This tally with whatever it left out that [knownTxIds] now say is
  /// ArDrive's counted in.
  ArSpendTally reclaim(Set<String> knownTxIds) {
    final found = excluded.keys.where(knownTxIds.contains).toList();
    final base = runBase?.reclaim(knownTxIds);

    if (found.isEmpty && identical(base, runBase)) {
      return this;
    }

    return ArSpendTally(
      winston: found.fold(winston, (sum, id) => sum + excluded[id]!),
      uploads: uploads + found.length,
      lastHeight: lastHeight,
      runMinHeight: runMinHeight,
      cursor: cursor,
      runBase: base,
      excluded: {
        for (final entry in excluded.entries)
          if (!knownTxIds.contains(entry.key)) entry.key: entry.value,
      },
    );
  }
}

/// [current] with [more] added, keeping the most recent
/// [ArSpendTally.maxExcluded].
Map<String, BigInt> _withExcluded(
  Map<String, BigInt> current,
  Map<String, BigInt> more,
) {
  final all = {...current, ...more};

  if (all.length <= ArSpendTally.maxExcluded) {
    return all;
  }

  return Map.fromEntries(
    all.entries.skip(all.length - ArSpendTally.maxExcluded),
  );
}

/// Counts what a wallet has paid in AR, a little at a time.
///
/// Remembers what it has counted, under [storageKey], so the first count is
/// the only long one: each later count asks only for blocks after the last
/// one counted. No count makes more than [maxPages] requests; one that would
/// carries on where it stopped next time, and says the figure so far is a
/// lower bound.
///
/// Any request that fails ends the count with what was already counted,
/// rather than with nothing. A count that was carrying on from a cursor is
/// set back to where it began, so the next one starts it again from its
/// first page: a cursor that has stopped working would otherwise fail every
/// time, and the figure would say "at least" forever.
Future<ArSpendTally> tallyArSpend({
  required String storageKey,
  required String? Function(String key) read,
  required Future<void> Function(String key, String value) write,
  required Future<ArFeePage> Function({required int minHeight, String? after})
      fetchPage,
  KnownTxLookup? knownAmong,
  int maxPages = 10,
}) async {
  final stored = ArSpendTally.fromJson(read(storageKey)) ?? ArSpendTally.empty;

  // What an earlier count left out, before sync knew it was ArDrive's. Only
  // those are asked about, and only when there are any.
  var tally = stored.reclaim(
    await lookUpKnown(knownAmong, stored.excludedIds),
  );

  // What this count adds to, kept until it finishes.
  final base = tally.runBase ??
      ArSpendTally(
        winston: tally.winston,
        uploads: tally.uploads,
        lastHeight: tally.lastHeight,
        excluded: tally.excluded,
      );
  final minHeight = tally.runMinHeight ?? tally.lastHeight + 1;
  var cursor = tally.cursor;
  var winston = tally.winston;
  var uploads = tally.uploads;
  var lastHeight = tally.lastHeight;
  var excluded = tally.excluded;

  for (var page = 0; page < maxPages; page++) {
    final ArFeePage result;

    try {
      result = await fetchPage(minHeight: minHeight, after: cursor);
    } catch (_) {
      if (cursor != null) {
        await write(storageKey, jsonEncode(base.toJson()));
      }

      return tally;
    }

    winston += result.winston;
    uploads += result.count;
    excluded = _withExcluded(excluded, result.excluded);
    if (result.lastHeight != null && result.lastHeight! > lastHeight) {
      lastHeight = result.lastHeight!;
    }

    tally = ArSpendTally(
      winston: winston,
      uploads: uploads,
      lastHeight: lastHeight,
      runMinHeight: result.hasMore ? minHeight : null,
      cursor: result.hasMore ? result.cursor : null,
      runBase: result.hasMore ? base : null,
      excluded: excluded,
    );
    await write(storageKey, jsonEncode(tally.toJson()));

    if (!result.hasMore) {
      break;
    }

    cursor = result.cursor;
  }

  return tally;
}

/// One page as the gateway answered it, before deciding what it means.
class RawFeePage {
  const RawFeePage({
    required this.page,
    required this.rows,
    required this.unbundledRows,
  });

  /// What the page adds up to: ArDrive's unbundled transactions only.
  final ArFeePage page;

  /// Every row the gateway returned, bundled or not.
  final int rows;

  /// Rows that are transactions of their own, not data items in a bundle.
  final int unbundledRows;
}

/// How to ask a gateway for a wallet's own transactions without the data
/// items in bundles - which are free to the wallet, and for a Turbo user are
/// every upload they ever made.
///
/// The standard filter, `bundledIn: null`, is ignored by ar.io gateways
/// (ardrive.net among them): they return the data items anyway, so a Turbo
/// user's count paged through every upload and never finished. Those
/// gateways do honour `bundledIn: [""]`, which is not in any spec. So that is
/// asked first, and a gateway that answers it with nothing is asked once the
/// standard way: if that brings back transactions of their own, this gateway
/// honours `null`, and is asked that way from then on.
class UnbundledFilter {
  /// Whether to ask with `[""]` rather than `null`.
  bool useEmptyId = true;

  /// The filter to send.
  List<String>? get bundledIn => useEmptyId ? const [''] : null;
}

/// A page of [UnbundledFilter]-filtered transactions, learning which filter
/// the gateway honours on the way. Costs a second request only when the
/// first page of a count is empty.
Future<ArFeePage> fetchDirectFeesPage({
  required UnbundledFilter filter,
  required bool firstPage,
  required Future<RawFeePage> Function(List<String>? bundledIn) fetch,
}) async {
  final raw = await fetch(filter.bundledIn);

  if (!filter.useEmptyId || !firstPage || raw.rows > 0) {
    return raw.page;
  }

  final standard = await fetch(null);

  if (standard.unbundledRows > 0) {
    filter.useEmptyId = false;
    return standard.page;
  }

  // Nothing of its own either way: a wallet that only ever used Turbo.
  return raw.page;
}

/// Which of [txIds] the wallet's synced drives are made of. See
/// `DriveDao.arDriveTransactionsAmong`.
typedef KnownTxLookup = Future<Set<String>> Function(Set<String> txIds);

/// [knownAmong] asked about [txIds], and nothing asked when there is nothing
/// to ask. A lookup that fails knows nothing: what it would have counted is
/// left out for now, and asked about again by the next count.
Future<Set<String>> lookUpKnown(
  KnownTxLookup? knownAmong,
  Set<String> txIds,
) async {
  if (knownAmong == null || txIds.isEmpty) {
    return const {};
  }

  try {
    return await knownAmong(txIds);
  } catch (_) {
    return const {};
  }
}

/// Whether a transaction a wallet paid for is ArDrive storage.
///
/// First by what sync knows: [knownTxIds] are the transactions the wallet's
/// synced drives are made of, data and bundles included - see
/// `DriveDao.arDriveTransactionIds`. Then by tag, for what has not synced
/// yet: an `ArFS` tag, which every file and folder metadata transaction
/// carries, or an App-Name one of ArDrive's apps has written.
///
/// The tags alone missed what matters most: the data transaction of a direct
/// upload is the costly part, and it carries an App-Name but no `ArFS` tag.
bool isArDriveTransaction({
  required String txId,
  required Map<String, String> tags,
  required Set<String> knownTxIds,
}) =>
    knownTxIds.contains(txId) || isArDriveByTags(tags);

/// Whether a transaction's tags alone say it is ArDrive's: an `ArFS` tag, or
/// an App-Name of one of ArDrive's apps. What they leave open is for
/// [isArDriveTransaction]'s known transactions to settle.
bool isArDriveByTags(Map<String, String> tags) =>
    tags.containsKey('ArFS') || arDriveAppNames.contains(tags['App-Name']);

/// What a wallet paid for one of its ArDrive transactions, in winston: the
/// network's fee, and the tip a direct upload sent ArDrive's community with
/// it.
///
/// The tip travels as the transaction's own transfer to a token holder,
/// tagged `Tip-Type`, so it is not in the fee. Any other transfer is not a
/// payment for storage and is left out.
BigInt arDrivePayment({
  required String feeWinston,
  required String quantityWinston,
  required Map<String, String> tags,
}) {
  final fee = BigInt.tryParse(feeWinston) ?? BigInt.zero;

  if (!tags.containsKey('Tip-Type')) {
    return fee;
  }

  return fee + (BigInt.tryParse(quantityWinston) ?? BigInt.zero);
}

/// The App-Name values ArDrive's apps have tagged uploads with: a fallback
/// for transactions sync has not recorded yet.
const arDriveAppNames = {
  'ArDrive-App',
  'ArDrive-Web',
  'ArDrive-CLI',
  'ArDrive-Core',
  'ArDrive-Desktop',
  'ArDrive-Sync',
};
