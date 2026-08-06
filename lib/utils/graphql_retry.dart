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
/// On 429 or 5xx errors, falls back to arweave.net/graphql (Goldsky proxy)
/// since most AR.IO gateways don't index ArDrive L2 data.
class GraphQLRetry {
  GraphQLRetry(this._client,
      {required InternetChecker internetChecker,
      String? fallbackGraphqlUrl})
      : _internetChecker = internetChecker,
        _fallbackGraphqlUrl =
            fallbackGraphqlUrl ?? 'https://arweave.net/graphql';

  final ArtemisClient _client;
  final InternetChecker _internetChecker;
  final String _fallbackGraphqlUrl;

  /// Attempts against the *primary* endpoint before falling back.
  ///
  /// This was 8, which `package:retry`'s exponential backoff turns into about
  /// 25 seconds (200ms doubling: 0.2 + 0.4 + 0.8 + 1.6 + 3.2 + 6.4 + 12.8)
  /// spent on an endpoint that is usually not coming back, *before* the
  /// fallback below is tried at all. Retrying a gateway that is down does not
  /// recover the query - switching endpoints does - so the cheapest way to
  /// answer faster is to reach the fallback sooner.
  ///
  /// Three keeps one real retry for a transient blip (~0.6s of backoff) and
  /// gets to the fallback in under a second. It applies to every GraphQL call
  /// in the app, sync included, which is why it is stated here once rather
  /// than tuned per call site.
  static const defaultMaxAttempts = 3;

  Future<GraphQLResponse<T>> execute<T, U extends JsonSerializable>(
    GraphQLQuery<T, U> query, {
    Function(Exception e)? onRetry,
    int maxAttempts = defaultMaxAttempts,
  }) async {
    // Try primary first
    try {
      return await _executeWithRetry(_client, query,
          onRetry: onRetry, maxAttempts: maxAttempts);
    } catch (primaryError) {
      // If primary exhausted all retries, try fallback
      final errorStr = primaryError.toString();
      if (errorStr.contains('429') ||
          errorStr.contains('500') ||
          errorStr.contains('502') ||
          errorStr.contains('503') ||
          errorStr.contains('504')) {
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

      // Primary failed (and fallback failed or wasn't attempted)
      final isConnected = await _internetChecker.isConnected();

      logger.e(
        'Fatal error while querying: ${query.operationName}. '
        'Number of retries exceeded',
        primaryError,
      );

      if (!isConnected) {
        throw NoConnectionException();
      }

      if (primaryError.toString().contains('FormatException')) {
        throw GraphQLException(
            const FormatException('Returned data is not a valid JSON.'));
      }

      throw GraphQLException(primaryError);
    }
  }

  Future<GraphQLResponse<T>> _executeWithRetry<T, U extends JsonSerializable>(
    ArtemisClient client,
    GraphQLQuery<T, U> query, {
    Function(Exception e)? onRetry,
    int maxAttempts = defaultMaxAttempts,
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
