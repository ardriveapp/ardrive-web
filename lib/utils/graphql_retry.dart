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
/// On 429 or 5xx errors, falls back to Goldsky since most AR.IO gateways don't
/// index ArDrive L2 data.
class GraphQLRetry {
  GraphQLRetry(this._client,
      {required InternetChecker internetChecker,
      String? fallbackGraphqlUrl})
      : _internetChecker = internetChecker,
        _fallbackGraphqlUrl =
            fallbackGraphqlUrl ?? defaultFallbackGraphqlUrl;

  /// Where a query goes when the primary endpoint will not serve it.
  ///
  /// Goldsky directly, rather than `arweave.net/graphql`, which is a proxy in
  /// front of this same index: going through it adds a hop that applies its
  /// own rate limiting, so a fallback armed *because* the primary returned 429
  /// could arrive at another 429 earned by nobody. The backend answering is
  /// the same either way.
  ///
  /// Note this endpoint clamps `first` above 100 to 100 edges while still
  /// reporting `hasNextPage: false`, so a paginating caller must not ask it
  /// for more than 100.
  static const defaultFallbackGraphqlUrl =
      'https://arweave-search.goldsky.com/graphql';

  final ArtemisClient _client;
  final InternetChecker _internetChecker;
  final String _fallbackGraphqlUrl;

  /// Attempts against the *primary* endpoint before falling back.
  ///
  /// This was 8. `package:retry` sleeps `200ms * 2^attempt` before each retry,
  /// so 8 attempts is 7 sleeps - 0.4 + 0.8 + 1.6 + 3.2 + 6.4 + 12.8 + 25.6 =
  /// **about 51 seconds** - spent on an endpoint that is usually not coming
  /// back, *before* the fallback below is tried at all. Retrying a gateway
  /// that is down does not recover the query; switching endpoints does.
  ///
  /// Five is the compromise. It spends ~6 seconds (0.4 + 0.8 + 1.6 + 3.2) on
  /// the primary, which still rides out an ordinary blip, and reaches the
  /// fallback roughly eight times sooner than before. Three was tempting but
  /// too sharp: the fallback only arms for 429 and 5xx (see below), so a
  /// dropped socket, a CORS failure, a DNS hiccup or any GraphQL `errors`
  /// payload gets no second endpoint at all - for those, this budget is the
  /// only resilience there is, and sync's paginated loop leans on it.
  ///
  /// It applies to every GraphQL call in the app, which is why it is stated
  /// here once rather than tuned per call site.
  static const defaultMaxAttempts = 5;

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
