import 'package:ardrive/utils/exceptions.dart';
import 'package:ardrive/utils/internet_checker.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:artemis/client.dart';
import 'package:artemis/schema/graphql_query.dart';
import 'package:artemis/schema/graphql_response.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:retry/retry.dart';

/// Retry every GraphQL query for `ArtemisClient`
class GraphQLRetry {
  GraphQLRetry(this._client,
      {required InternetChecker internetChecker, ArioSDK? arioSDK})
      : _internetChecker = internetChecker,
        _arioSDK = arioSDK;

  ArtemisClient _client;
  final InternetChecker _internetChecker;
  final ArioSDK? _arioSDK;

  int currentGatewayIndex = 0;

  Future<GraphQLResponse<T>> execute<T, U extends JsonSerializable>(
    GraphQLQuery<T, U> query, {
    Function(Exception e)? onRetry,
    int maxAttempts = 8,
  }) async {
    try {
      final queryResponse = await retry(
        () async {
          final response = await _client.execute(query);
          if (response.errors != null && response.errors!.isNotEmpty) {
            throw GraphQLException(response.errors);
          }
          return response;
        },
        maxAttempts: maxAttempts,
        onRetry: (exception) async {
          if (exception.toString().contains('429')) {
            final gateways = await _arioSDK?.getGateways();

            if (gateways != null && gateways.isNotEmpty) {
              _client = ArtemisClient(
                'https://${gateways[currentGatewayIndex].settings.fqdn}/graphql',
              );

              ++currentGatewayIndex;
            }
          }

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

      throw GraphQLException(exception);
    }
  }
}

class GraphQLException implements Exception {
  final Object? exception;

  GraphQLException([this.exception]);

  @override
  String toString() {
    return 'GraphQLException: $exception';
  }
}
