import 'package:ardrive/permanence/ar_spend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, String> storage;
  late List<({int minHeight, String? after})> asked;

  setUp(() {
    storage = {};
    asked = [];
  });

  ArFeePage page(int winston, int count, int? lastHeight,
          {String? cursor,
          bool hasMore = false,
          Map<String, int> excluded = const {}}) =>
      ArFeePage(
        winston: BigInt.from(winston),
        count: count,
        lastHeight: lastHeight,
        cursor: cursor,
        hasMore: hasMore,
        excluded: {
          for (final e in excluded.entries) e.key: BigInt.from(e.value)
        },
      );

  Future<ArSpendTally> tally(
    List<ArFeePage> pages, {
    int maxPages = 10,
    bool failOnFirst = false,
    Set<String> known = const {},
  }) {
    var next = 0;
    return tallyArSpend(
      storageKey: 'key',
      read: (key) => storage[key],
      write: (key, value) async => storage[key] = value,
      maxPages: maxPages,
      knownTxIds: known,
      fetchPage: ({required int minHeight, String? after}) async {
        asked.add((minHeight: minHeight, after: after));
        if (failOnFirst) throw Exception('gateway down');
        return pages[next++];
      },
    );
  }

  test('a wallet that only used Turbo costs one empty request', () async {
    final result = await tally([page(0, 0, null)]);

    expect(result.winston, BigInt.zero);
    expect(result.uploads, 0);
    expect(result.complete, isTrue);
    expect(asked, hasLength(1));
  });

  test('adds up every page', () async {
    final result = await tally([
      page(100, 100, 10, cursor: 'a', hasMore: true),
      page(50, 30, 12),
    ]);

    expect(result.winston, BigInt.from(150));
    expect(result.uploads, 130);
    expect(result.lastHeight, 12);
    expect(result.complete, isTrue);
    expect(asked.map((a) => a.after), [null, 'a']);
  });

  test('later counts ask only for blocks after the last one counted', () async {
    await tally([page(100, 3, 500)]);
    asked.clear();

    final result = await tally([page(20, 1, 600)]);

    expect(asked.single.minHeight, 501);
    expect(result.winston, BigInt.from(120));
    expect(result.uploads, 4);
  });

  test('never makes more than its page limit, and carries on next time',
      () async {
    final first = await tally(
      [
        page(10, 100, 1, cursor: 'p1', hasMore: true),
        page(10, 100, 2, cursor: 'p2', hasMore: true),
      ],
      maxPages: 2,
    );

    expect(asked, hasLength(2));
    expect(first.complete, isFalse, reason: 'a lower bound so far');
    expect(first.winston, BigInt.from(20));

    asked.clear();
    final second = await tally([page(5, 40, 3)], maxPages: 2);

    // From where it stopped: the same run, the next page.
    expect(asked.single, (minHeight: 0, after: 'p2'));
    expect(second.winston, BigInt.from(25));
    expect(second.complete, isTrue);
  });

  test(
      'a cursor that stops working starts its count again, counting nothing '
      'twice', () async {
    // A gateway switched, a cursor expired: the unfinished count cannot go on.
    await tally([page(100, 3, 500)]);
    await tally(
      [page(10, 100, 600, cursor: 'stale', hasMore: true)],
      maxPages: 1,
    );
    asked.clear();

    final failed = await tally([], failOnFirst: true);
    expect(failed.winston, BigInt.from(110), reason: 'shown as it was');

    asked.clear();
    final restarted = await tally([
      page(10, 100, 600, cursor: 'fresh', hasMore: true),
      page(5, 20, 700),
    ]);

    // From the start of that count, not from the dead cursor.
    expect(asked.first, (minHeight: 501, after: null));
    expect(restarted.winston, BigInt.from(115));
    expect(restarted.uploads, 123);
    expect(restarted.complete, isTrue);
  });

  group('a transaction left out before its drive synced', () {
    test('is counted once sync knows it, without asking again', () async {
      // The data of a direct upload: no tag says it is ArDrive's, and its
      // drive had not synced when this count passed it.
      await tally([
        page(100, 1, 500, excluded: {'late-data': 40})
      ]);
      asked.clear();

      final later = await tally([page(0, 0, null)], known: {'late-data'});

      expect(later.winston, BigInt.from(140));
      expect(later.uploads, 2);
      expect(later.excluded, isEmpty);
      expect(asked.single.minHeight, 501, reason: 'not counted again');
    });

    test('is counted only once', () async {
      await tally([
        page(0, 0, 500, excluded: {'late-data': 40})
      ]);
      await tally([page(0, 0, null)], known: {'late-data'});

      final again = await tally([page(0, 0, null)], known: {'late-data'});

      expect(again.winston, BigInt.from(40));
    });

    test('one from another app stays left out, and remembered', () async {
      final result = await tally(
        [
          page(0, 0, 500, excluded: {'arkb-upload': 9})
        ],
        known: {'something-else'},
      );

      expect(result.winston, BigInt.zero);
      expect(ArSpendTally.fromJson(storage['key'])!.excluded.keys,
          ['arkb-upload']);
    });

    test('keeps only the most recent of them', () async {
      final many = {
        for (var i = 0; i < ArSpendTally.maxExcluded + 10; i++) 'tx-$i': 1
      };

      final result = await tally([page(0, 0, 500, excluded: many)]);

      expect(result.excluded, hasLength(ArSpendTally.maxExcluded));
      expect(result.excluded.containsKey('tx-0'), isFalse);
      expect(result.excluded.containsKey('tx-${ArSpendTally.maxExcluded + 9}'),
          isTrue);
    });
  });

  test('a failed request keeps what was already counted', () async {
    await tally([page(100, 3, 500)]);

    final result = await tally([], failOnFirst: true);

    expect(result.winston, BigInt.from(100));
    expect(result.uploads, 3);
  });

  test('a stored tally it cannot read is started again', () async {
    storage['key'] = 'not json';

    final result = await tally([page(7, 1, 9)]);

    expect(result.winston, BigInt.from(7));
    expect(asked.single.minHeight, 0);
  });

  group('what one transaction cost', () {
    test('is its fee', () {
      expect(
        arDrivePayment(
          feeWinston: '100',
          quantityWinston: '0',
          tags: const {'App-Name': 'ArDrive-App'},
        ),
        BigInt.from(100),
      );
    });

    test("adds the tip a direct upload sent ArDrive's community", () {
      expect(
        arDrivePayment(
          feeWinston: '100',
          quantityWinston: '15',
          tags: const {'App-Name': 'ArDrive-App', 'Tip-Type': 'data upload'},
        ),
        BigInt.from(115),
      );
    });

    test('leaves out a transfer that is not a tip', () {
      expect(
        arDrivePayment(
          feeWinston: '100',
          quantityWinston: '5000',
          tags: const {'App-Name': 'ArDrive-App'},
        ),
        BigInt.from(100),
      );
    });
  });

  test('a winston is a trillionth of an AR', () {
    final tally = ArSpendTally(
      winston: BigInt.from(1500000000000),
      uploads: 1,
      lastHeight: 1,
    );

    expect(tally.ar, 1.5);
  });

  group('asking only for transactions of the wallet itself', () {
    RawFeePage raw({required int rows, required int unbundled, int ar = 0}) =>
        RawFeePage(
          page: ArFeePage(
            winston: BigInt.from(ar),
            count: unbundled,
            lastHeight: rows == 0 ? null : 10,
            cursor: null,
            hasMore: false,
          ),
          rows: rows,
          unbundledRows: unbundled,
        );

    test('an ar.io gateway, which honours [""], is asked once', () async {
      final filter = UnbundledFilter();
      final asked = <List<String>?>[];

      final page = await fetchDirectFeesPage(
        filter: filter,
        firstPage: true,
        fetch: (bundledIn) async {
          asked.add(bundledIn);
          return raw(rows: 100, unbundled: 100, ar: 7);
        },
      );

      expect(asked, [
        ['']
      ]);
      expect(page.winston, BigInt.from(7));
      expect(filter.useEmptyId, isTrue);
    });

    test('a wallet that only used Turbo costs two requests, and is zero',
        () async {
      // [""] finds nothing; null on an ar.io gateway brings back only the
      // wallet's data items, which are not its own transactions.
      final filter = UnbundledFilter();
      final asked = <List<String>?>[];

      final page = await fetchDirectFeesPage(
        filter: filter,
        firstPage: true,
        fetch: (bundledIn) async {
          asked.add(bundledIn);
          return bundledIn == null
              ? raw(rows: 100, unbundled: 0)
              : raw(rows: 0, unbundled: 0);
        },
      );

      expect(asked, [
        [''],
        null
      ]);
      expect(page.winston, BigInt.zero);
      expect(filter.useEmptyId, isTrue, reason: 'nothing learned about null');
    });

    test(
        'a gateway that honours null, not [""], is asked with null from then '
        'on', () async {
      final filter = UnbundledFilter();
      final asked = <List<String>?>[];

      Future<RawFeePage> gateway(List<String>? bundledIn) async {
        asked.add(bundledIn);
        return bundledIn == null
            ? raw(rows: 100, unbundled: 100, ar: 9)
            : raw(rows: 0, unbundled: 0);
      }

      final first = await fetchDirectFeesPage(
          filter: filter, firstPage: true, fetch: gateway);
      await fetchDirectFeesPage(
          filter: filter, firstPage: false, fetch: gateway);

      expect(first.winston, BigInt.from(9));
      expect(filter.useEmptyId, isFalse);
      expect(asked, [
        [''],
        null,
        null
      ]);
    });

    test('an empty page part-way through a count asks nothing more', () async {
      final asked = <List<String>?>[];

      await fetchDirectFeesPage(
        filter: UnbundledFilter(),
        firstPage: false,
        fetch: (bundledIn) async {
          asked.add(bundledIn);
          return raw(rows: 0, unbundled: 0);
        },
      );

      expect(asked, hasLength(1));
    });
  });

  group('what counts as ArDrive storage', () {
    test('a transaction a synced drive is made of, whatever its tags', () {
      // The data of a direct upload: costly, and with no ArFS tag.
      expect(
        isArDriveTransaction(
          txId: 'data-tx',
          tags: const {'Content-Type': 'video/mp4'},
          knownTxIds: const {'data-tx'},
        ),
        isTrue,
      );
    });

    test('by tag, for what has not synced yet', () {
      expect(
        isArDriveTransaction(
          txId: 'x',
          tags: const {'ArFS': '0.11'},
          knownTxIds: const {},
        ),
        isTrue,
      );
      expect(
        isArDriveTransaction(
          txId: 'x',
          tags: const {'App-Name': 'ArDrive-Web'},
          knownTxIds: const {},
        ),
        isTrue,
      );
    });

    test('not another app', () {
      expect(
        isArDriveTransaction(
          txId: 'x',
          tags: const {'App-Name': 'arkb'},
          knownTxIds: const {'something-else'},
        ),
        isFalse,
      );
    });
  });
}
