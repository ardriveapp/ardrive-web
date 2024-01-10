import 'package:ardrive/utils/exceptions.dart';
import 'package:ardrive/utils/internet_checker.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:artemis/client.dart';
import 'package:artemis/schema/graphql_query.dart';
import 'package:artemis/schema/graphql_response.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:retry/retry.dart';

/// Retry every GraphQL query for `ArtemisClient`
class GraphQLRetry {
  GraphQLRetry(this._client, {required InternetChecker internetChecker})
      : _internetChecker = internetChecker;

  final ArtemisClient _client;
  final InternetChecker _internetChecker;

  Future<GraphQLResponse<T>> execute<T, U extends JsonSerializable>(
    GraphQLQuery<T, U> query, {
    Function(Exception e)? onRetry,
    int maxAttempts = 8,
  }) async {
    try {
      final queryResponse = await retry(
        () async => await _client.execute(query),
        maxAttempts: maxAttempts,
        onRetry: (exception) {
          onRetry?.call(exception);
          logger.w('Retrying Query: ${query.operationName}');
        },
      );

      return queryResponse;
    } catch (e) {
      final isConnected = await _internetChecker.isConnected();

      logger.e(
        'Fatal error while querying: ${query.operationName}. Number of retries exceeded',
        e,
      );

      if (!isConnected) {
        throw NoConnectionException();
      }

      late Object exception;

      if (e.toString().contains('FormatException')) {
        exception = const FormatException('Returned data is not a valid JSON.');
      } else {
        exception = e;
      }

      throw exception;
    }
  }
}
