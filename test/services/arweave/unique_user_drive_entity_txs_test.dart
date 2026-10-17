import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/utils/graphql_retry.dart';
import 'package:ardrive/utils/internet_checker.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:artemis/artemis.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

class _MockArtemisClient extends Mock implements ArtemisClient {}

class _MockInternetChecker extends Mock implements InternetChecker {}

typedef _Tx
    = UserDriveEntities$Query$TransactionConnection$TransactionEdge$Transaction;

/// Answers `UserDriveEntities` one page at a time, in the order given, the way
/// a gateway would: `hasNextPage` is true on every page but the last.
class _PagedRetry extends GraphQLRetry {
  _PagedRetry(this._pages)
      : super(_MockArtemisClient(), internetChecker: _MockInternetChecker());

  final List<List<_Tx>> _pages;

  int _next = 0;

  @override
  Future<GraphQLResponse<T>> execute<T, U extends JsonSerializable>(
    GraphQLQuery<T, U> query, {
    Function(Exception e)? onRetry,
    int maxAttempts = GraphQLRetry.defaultMaxAttempts,
  }) async {
    final page = _pages[_next];
    final isLast = _next == _pages.length - 1;
    _next++;

    final data = UserDriveEntities$Query()
      ..transactions = (UserDriveEntities$Query$TransactionConnection()
        ..edges = [
          for (final tx in page)
            UserDriveEntities$Query$TransactionConnection$TransactionEdge()
              ..node = tx
              ..cursor = tx.id,
        ]
        ..pageInfo = (UserDriveEntities$Query$TransactionConnection$PageInfo()
          ..hasNextPage = !isLast));

    return GraphQLResponse<T>(data: data as T);
  }
}

/// A drive's entity transactions can share a block, and the gateway lists
/// those in whatever order it likes. The drive list has to pick the newest
/// revision anyway, or a drive that was renamed and then hidden in one block
/// comes back unhidden on the next device.
void main() {
  const owner = 'owner-address';
  const driveId = '70802dc8-63a4-48c5-b3f7-e6946f8553e6';
  const block = 2019598;

  _Tx driveTx(
    String id, {
    required int? height,
    required int unixTime,
    String drive = driveId,
  }) =>
      _Tx()
        ..id = id
        ..owner = (TransactionCommonMixin$Owner()..address = owner)
        ..block = height == null
            ? null
            : (TransactionCommonMixin$Block()
              ..height = height
              ..timestamp = 0)
        ..tags = [
          TransactionCommonMixin$Tag()
            ..name = EntityTag.arFs
            ..value = '0.15',
          TransactionCommonMixin$Tag()
            ..name = EntityTag.entityType
            ..value = 'drive',
          TransactionCommonMixin$Tag()
            ..name = EntityTag.driveId
            ..value = drive,
          TransactionCommonMixin$Tag()
            ..name = EntityTag.unixTime
            ..value = '$unixTime',
        ];

  // The four transactions from the report, all in one block. Unix-Time is
  // 2026-10-12 UTC.
  final create = driveTx('LDcy', height: block, unixTime: 1791778064);
  final firstRename = driveTx('aXws', height: block, unixTime: 1791778162);
  final secondRename = driveTx('stzt', height: block, unixTime: 1791778214);
  final hide = driveTx('XWmU', height: block, unixTime: 1791778223);

  ArweaveService serviceWith(List<List<_Tx>> pages) {
    final configService = MockConfigService();
    final config = MockConfig();

    when(() => configService.config).thenReturn(config);
    when(() => config.arweaveGatewayUrl).thenReturn('https://arweave.net');

    final service = ArweaveService(
      MockArweave(),
      MockArDriveCrypto(),
      MockDriveDao(),
      configService,
      artemisClient: _MockArtemisClient(),
    );

    service.graphQLRetry = _PagedRetry(pages);

    return service;
  }

  Future<List<String>> idsFor(List<List<_Tx>> pages) async {
    final txs = await serviceWith(pages).getUniqueUserDriveEntityTxs(owner);
    return txs.map((tx) => tx.id).toList();
  }

  test('inside one block, the latest Unix-Time wins, in the order reported',
      () async {
    // The order turbo-gateway.com returned for HEIGHT_DESC.
    expect(
      await idsFor([
        [secondRename, firstRename, hide, create],
      ]),
      ['XWmU'],
    );
  });

  test('and in any other order', () async {
    final orders = [
      [create, firstRename, secondRename, hide],
      [hide, secondRename, firstRename, create],
      [firstRename, hide, create, secondRename],
    ];

    for (final order in orders) {
      expect(await idsFor([order]), ['XWmU'], reason: 'order: $order');
    }
  });

  test('a drive split across pages still comes back once, as its newest',
      () async {
    expect(
      await idsFor([
        [secondRename, firstRename],
        [hide, create],
      ]),
      ['XWmU'],
    );
  });

  test('a higher block wins over a later Unix-Time in a lower one', () async {
    // Unix-Time is the uploader's clock. Across blocks the chain's order
    // stands, as it does in sync.
    final later = driveTx('later-block', height: block + 1, unixTime: 1);

    expect(
      await idsFor([
        [hide, later],
      ]),
      ['later-block'],
    );
  });

  test('a pending transaction wins over a mined one', () async {
    final pending = driveTx('pending', height: null, unixTime: 1);

    expect(
      await idsFor([
        [hide],
        [pending],
      ]),
      ['pending'],
    );
  });

  test('a tie on block and Unix-Time keeps the one listed first', () async {
    final twin = driveTx('twin', height: block, unixTime: 1791778223);

    expect(
      await idsFor([
        [twin, hide],
      ]),
      ['twin'],
    );
  });

  test('drives keep the order they were first listed in', () async {
    final other = driveTx('other', height: block, unixTime: 1, drive: 'd2');

    expect(
      await idsFor([
        [secondRename, other, hide],
      ]),
      ['XWmU', 'other'],
    );
  });

  test('a bad Unix-Time loses the tie instead of throwing', () async {
    // Missing, not a number, and a number DateTime cannot hold, which
    // getCommitTime reads as milliseconds and then throws a RangeError on.
    // Any of these escaping would fail discovery for the whole wallet.
    final badValues = <String?>[null, 'not-a-number', '9000000000000000'];

    for (final value in badValues) {
      final bad = driveTx('bad', height: block, unixTime: 0);
      bad.tags.removeWhere((t) => t.name == EntityTag.unixTime);
      if (value != null) {
        bad.tags.add(TransactionCommonMixin$Tag()
          ..name = EntityTag.unixTime
          ..value = value);
      }

      expect(
        await idsFor([
          [bad, hide],
        ]),
        ['XWmU'],
        reason: 'Unix-Time: $value, listed first',
      );
      expect(
        await idsFor([
          [hide, bad],
        ]),
        ['XWmU'],
        reason: 'Unix-Time: $value, listed second',
      );
    }
  });
}
