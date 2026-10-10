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
  });

  /// The fees on this page.
  final BigInt winston;

  /// Transactions on this page.
  final int count;

  /// The block height of the page's last transaction, if it had any.
  final int? lastHeight;

  /// Where the next page starts.
  final String? cursor;

  final bool hasMore;
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
      };

  static ArSpendTally? fromJson(String? source) {
    if (source == null) {
      return null;
    }

    try {
      final json = jsonDecode(source) as Map<String, dynamic>;
      return ArSpendTally(
        winston: BigInt.parse(json['winston'] as String),
        uploads: json['uploads'] as int,
        lastHeight: json['lastHeight'] as int,
        runMinHeight: json['runMinHeight'] as int?,
        cursor: json['cursor'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
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
/// rather than with nothing.
Future<ArSpendTally> tallyArSpend({
  required String storageKey,
  required String? Function(String key) read,
  required Future<void> Function(String key, String value) write,
  required Future<ArFeePage> Function({required int minHeight, String? after})
      fetchPage,
  int maxPages = 10,
}) async {
  var tally = ArSpendTally.fromJson(read(storageKey)) ?? ArSpendTally.empty;

  final minHeight = tally.runMinHeight ?? tally.lastHeight + 1;
  var cursor = tally.cursor;
  var winston = tally.winston;
  var uploads = tally.uploads;
  var lastHeight = tally.lastHeight;

  for (var page = 0; page < maxPages; page++) {
    final ArFeePage result;

    try {
      result = await fetchPage(minHeight: minHeight, after: cursor);
    } catch (_) {
      return tally;
    }

    winston += result.winston;
    uploads += result.count;
    if (result.lastHeight != null && result.lastHeight! > lastHeight) {
      lastHeight = result.lastHeight!;
    }

    tally = ArSpendTally(
      winston: winston,
      uploads: uploads,
      lastHeight: lastHeight,
      runMinHeight: result.hasMore ? minHeight : null,
      cursor: result.hasMore ? result.cursor : null,
    );
    await write(storageKey, jsonEncode(tally.toJson()));

    if (!result.hasMore) {
      break;
    }

    cursor = result.cursor;
  }

  return tally;
}
