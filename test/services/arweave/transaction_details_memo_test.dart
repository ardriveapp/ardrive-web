import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/utils/graphql_retry.dart';
import 'package:ardrive/utils/internet_checker.dart';
import 'package:artemis/artemis.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

class _MockArtemisClient extends Mock implements ArtemisClient {}

class _MockInternetChecker extends Mock implements InternetChecker {}

/// Counts requests instead of making them.
///
/// `GraphQLRetry` is a `late` field on [ArweaveService], so a test can put one
/// of these in its place and see exactly how many times a query reached the
/// network.
class _CountingRetry extends GraphQLRetry {
  _CountingRetry(this._answer)
      : super(_MockArtemisClient(), internetChecker: _MockInternetChecker());

  final TransactionDetails$Query$Transaction? Function() _answer;

  int executions = 0;

  @override
  Future<GraphQLResponse<T>> execute<T, U extends JsonSerializable>(
    GraphQLQuery<T, U> query, {
    Function(Exception e)? onRetry,
    int maxAttempts = GraphQLRetry.defaultMaxAttempts,
  }) async {
    executions++;

    final data = TransactionDetails$Query()..transaction = _answer();

    return GraphQLResponse<T>(data: data as T);
  }
}

/// A transaction is immutable, so asking for one twice is never anything but a
/// second round trip. Two callers on the shared file page ask for the same one
/// - the preview, for the cipher it decrypts with, and the download behind it
/// for the same tags - and on a rate-limited connection the second is the one
/// that fails.
void main() {
  const txId = 'Y_KKT8o1vCZWxFjgUnlPRUssaoCnZ2Pi-5aYabBFQRw';

  TransactionDetails$Query$Transaction transaction() =>
      TransactionDetails$Query$Transaction()
        ..id = txId
        ..tags = [
          TransactionCommonMixin$Tag()
            ..name = 'Cipher'
            ..value = 'AES256-GCM',
        ];

  ArweaveService serviceWith(_CountingRetry retry) {
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

    service.graphQLRetry = retry;

    return service;
  }

  test('the same transaction is fetched once, however many callers ask',
      () async {
    final retry = _CountingRetry(transaction);
    final service = serviceWith(retry);

    final first = await service.getTransactionDetails(txId);
    final second = await service.getTransactionDetails(txId);

    expect(first?.id, txId);
    expect(second?.id, txId);
    expect(retry.executions, 1);
  });

  test('callers that arrive together share one request', () async {
    final retry = _CountingRetry(transaction);
    final service = serviceWith(retry);

    // Neither awaits before the other starts, which is the preview and the
    // download racing on a page the recipient is clicking through.
    final results = await Future.wait([
      service.getTransactionDetails(txId),
      service.getTransactionDetails(txId),
    ]);

    expect(results.every((t) => t?.id == txId), isTrue);
    expect(retry.executions, 1);
  });

  test('a transaction that could not be read is asked for again', () async {
    // Not a fact worth remembering: a miss may be a rate limit, a gateway that
    // has not indexed it yet, or one that never will. The page retries those on
    // purpose.
    final retry = _CountingRetry(() => null);
    final service = serviceWith(retry);

    await service.getTransactionDetails(txId);
    await service.getTransactionDetails(txId);

    expect(retry.executions, 2);
  });
}
