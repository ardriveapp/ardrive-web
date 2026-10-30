import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/utils/graphql_retry.dart';
import 'package:ardrive/utils/internet_checker.dart';
import 'package:artemis/artemis.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

class _MockArtemisClient extends Mock implements ArtemisClient {}

class _MockInternetChecker extends Mock implements InternetChecker {}

/// Answers the drive activity probe with [_edges], as a gateway would.
class _ProbeRetry extends GraphQLRetry {
  _ProbeRetry(this._edges)
      : super(_MockArtemisClient(), internetChecker: _MockInternetChecker());

  /// Each one a transaction: its Drive-Id and block height (null: pending).
  final List<(String driveId, int? height)> _edges;

  DriveActivityProbeArguments? asked;

  @override
  Future<GraphQLResponse<T>> execute<T, U extends JsonSerializable>(
    GraphQLQuery<T, U> query, {
    Function(Exception e)? onRetry,
    int maxAttempts = GraphQLRetry.defaultMaxAttempts,
  }) async {
    asked = query.variables as DriveActivityProbeArguments;
    final data = query.parse({
      'transactions': {
        'pageInfo': {'hasNextPage': false},
        'edges': [
          for (final (driveId, height) in _edges)
            {
              'node': {
                'block': height == null ? null : {'height': height},
                'tags': [
                  {'name': 'Drive-Id', 'value': driveId},
                ],
              },
            },
        ],
      },
    });
    return GraphQLResponse<T>(data: data);
  }
}

void main() {
  ArweaveService serviceWith(_ProbeRetry retry) {
    final configService = MockConfigService();
    final config = MockConfig();
    when(() => configService.config).thenReturn(config);
    when(() => config.arweaveGatewayUrl).thenReturn('https://gateway.test');
    when(() => config.arweaveGatewayForDataRequest).thenReturn(
        const SelectedGateway(label: 'test', url: 'https://gateway.test'));

    return ArweaveService(
      MockArweave(),
      MockArDriveCrypto(),
      MockDriveDao(),
      configService,
      artemisClient: _MockArtemisClient(),
    )..graphQLRetry = retry;
  }

  // One query covers drives read up to different heights. A drive read at
  // 2000 has its own writes from 1500 in the answer to a query from 1001.
  test('a drive counts only for what is past its own read height', () async {
    final retry = _ProbeRetry([
      ('read-later', 1500),
      ('read-later', 2000),
      ('read-earlier', 1500),
    ]);

    final result = await serviceWith(retry).probeActiveDriveIds(
      driveIds: ['read-earlier', 'read-later'],
      minBlockHeight: 1001,
      ownerAddress: 'owner',
      readUpTo: {'read-earlier': 1000, 'read-later': 2000},
    );

    expect(result.activeDriveIds, {'read-earlier'});
    expect(result.isComplete, isTrue);
    expect(retry.asked!.minBlockHeight, 1001);
  });

  test('without read heights, every drive in the answer counts', () async {
    final retry = _ProbeRetry([('a', 1500), ('b', null)]);

    final result = await serviceWith(retry).probeActiveDriveIds(
      driveIds: ['a', 'b'],
      minBlockHeight: 1000,
      ownerAddress: 'owner',
    );

    expect(result.activeDriveIds, {'a', 'b'});
  });
}
