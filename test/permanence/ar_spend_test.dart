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
          {String? cursor, bool hasMore = false}) =>
      ArFeePage(
        winston: BigInt.from(winston),
        count: count,
        lastHeight: lastHeight,
        cursor: cursor,
        hasMore: hasMore,
      );

  Future<ArSpendTally> tally(
    List<ArFeePage> pages, {
    int maxPages = 10,
    bool failOnFirst = false,
  }) {
    var next = 0;
    return tallyArSpend(
      storageKey: 'key',
      read: (key) => storage[key],
      write: (key, value) async => storage[key] = value,
      maxPages: maxPages,
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

  test('a winston is a trillionth of an AR', () {
    final tally = ArSpendTally(
      winston: BigInt.from(1500000000000),
      uploads: 1,
      lastHeight: 1,
    );

    expect(tally.ar, 1.5);
  });
}
