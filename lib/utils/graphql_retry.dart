import 'package:ardrive/utils/exceptions.dart';
import 'package:ardrive/utils/internet_checker.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:artemis/client.dart';
import 'package:artemis/schema/graphql_query.dart';
import 'package:artemis/schema/graphql_response.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:retry/retry.dart';

/// Retry every GraphQL query for `ArtemisClient`
///
/// On 429 or 5xx errors, falls back to the Goldsky search index directly
/// (arweave.net/graphql proxies to it but rate-limits aggressively) since
/// most AR.IO gateways don't index ArDrive L2 data.
///
/// Note: Goldsky caps page size at 100 and, when asked for more, silently
/// clamps to 100 while reporting hasNextPage: false — so queries sent through
/// this fallback must never request more than 100 items per page.
class GraphQLRetry {
  GraphQLRetry(this._client,
      {required InternetChecker internetChecker,
      String? fallbackGraphqlUrl})
      : _internetChecker = internetChecker,
        _fallbackGraphqlUrl =
            fallbackGraphqlUrl ?? 'https://arweave-search.goldsky.com/graphql';

  final ArtemisClient _client;
  final InternetChecker _internetChecker;
  final String _fallbackGraphqlUrl;

  /// Executes [query] with retries.
  ///
  /// [allowFallback]: when true (default), a failed primary is retried once
  /// against the fallback endpoint. Paginated callers using page sizes above
  /// 100 or gateway-specific cursors must pass false and manage the fallback
  /// themselves: cursors are opaque, endpoint-specific values, and the
  /// fallback clamps pages above 100 while misreporting hasNextPage.
  ///
  /// [useFallbackEndpoint]: when true, the query is sent only to the
  /// fallback endpoint. Used by endpoint-sticky pagination.
  Future<GraphQLResponse<T>> execute<T, U extends JsonSerializable>(
    GraphQLQuery<T, U> query, {
    Function(Exception e)? onRetry,
    int maxAttempts = 8,
    bool allowFallback = true,
    bool useFallbackEndpoint = false,
  }) async {
    if (useFallbackEndpoint) {
      final fallbackClient = ArtemisClient(_fallbackGraphqlUrl);
      try {
        return await _executeWithRetry(fallbackClient, query,
            onRetry: onRetry, maxAttempts: maxAttempts);
      } catch (fallbackError) {
        throw await _terminalException(query, fallbackError);
      } finally {
        fallbackClient.dispose();
      }
    }

    // Try primary first
    try {
      return await _executeWithRetry(_client, query,
          onRetry: onRetry, maxAttempts: maxAttempts);
    } catch (primaryError) {
      // If primary exhausted all retries, try fallback
      final errorStr = primaryError.toString();
      if (allowFallback &&
          (errorStr.contains('429') ||
              errorStr.contains('500') ||
              errorStr.contains('502') ||
              errorStr.contains('503') ||
              errorStr.contains('504'))) {
        logger.w(
          'GraphQL primary exhausted retries, '
          'trying fallback: $_fallbackGraphqlUrl',
        );

        final fallbackClient = ArtemisClient(_fallbackGraphqlUrl);
        try {
          final result = await _executeWithRetry(fallbackClient, query,
              onRetry: onRetry, maxAttempts: 3);
          logger.i('GraphQL fallback succeeded for ${query.operationName}');
          return result;
        } catch (fallbackError) {
          logger.e(
            'GraphQL fallback also failed for ${query.operationName}',
            fallbackError,
          );
          // Fall through to unified error handling below
        } finally {
          fallbackClient.dispose();
        }
      }

      throw await _terminalException(query, primaryError);
    }
  }

  /// Builds the terminal exception for an exhausted query, matching the
  /// original error-classification behavior.
  Future<Exception> _terminalException<T, U extends JsonSerializable>(
    GraphQLQuery<T, U> query,
    Object error,
  ) async {
    final isConnected = await _internetChecker.isConnected();

    logger.e(
      'Fatal error while querying: ${query.operationName}. '
      'Number of retries exceeded',
      error,
    );

    if (!isConnected) {
      return NoConnectionException();
    }

    if (error.toString().contains('FormatException')) {
      return GraphQLException(
          const FormatException('Returned data is not a valid JSON.'));
    }

    return GraphQLException(error);
  }

  Future<GraphQLResponse<T>> _executeWithRetry<T, U extends JsonSerializable>(
    ArtemisClient client,
    GraphQLQuery<T, U> query, {
    Function(Exception e)? onRetry,
    int maxAttempts = 8,
  }) {
    return retry(
      () async {
        final response = await client.execute(query);
        if (response.errors != null && response.errors!.isNotEmpty) {
          throw GraphQLException(response.errors);
        }
        return response;
      },
      maxAttempts: maxAttempts,
      onRetry: (exception) {
        onRetry?.call(exception);
        logger.w('Retrying Query: ${query.operationName}');
      },
    );
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
