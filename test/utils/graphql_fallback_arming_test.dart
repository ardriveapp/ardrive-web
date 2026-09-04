import 'package:ardrive/utils/graphql_retry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql_exec/gql_exec.dart' as gql;
import 'package:gql_http_link/gql_http_link.dart';
import 'package:gql_link/gql_link.dart';
import 'package:http/http.dart' as http;

/// Whether a failure sends the query to the other endpoint.
///
/// Reported from the browser: repeated retries against one gateway and never a
/// fallback, on a host known to rate-limit. The reason was that the decision
/// read `error.toString()` looking for '429' or a 5xx, and the exception a
/// non-2xx actually produces does not print its status code - it prints
/// originalException, originalStackTrace and parsedResponse. So the check was
/// false for every HTTP failure there is, and the fallback existed without
/// ever arming.
void main() {
  HttpLinkServerException serverError(int status) => HttpLinkServerException(
        response: http.Response('', status),
        parsedResponse: const gql.Response(response: {}),
      );

  group('an HTTP failure is read by its status, not its text', () {
    test('a rate limit sends the query elsewhere', () {
      expect(GraphQLRetry.deservesFallback(serverError(429)), isTrue);
    });

    test('so does a bad gateway', () {
      expect(GraphQLRetry.deservesFallback(serverError(502)), isTrue);
      expect(GraphQLRetry.deservesFallback(serverError(500)), isTrue);
      expect(GraphQLRetry.deservesFallback(serverError(503)), isTrue);
      expect(GraphQLRetry.deservesFallback(serverError(504)), isTrue);
    });

    test('and the whole 5xx range, not the four codes once listed', () {
      expect(GraphQLRetry.deservesFallback(serverError(507)), isTrue);
      expect(GraphQLRetry.deservesFallback(serverError(599)), isTrue);
    });

    /// None of these is fixed by asking a different endpoint the same thing.
    test('a bad request is not sent elsewhere to fail again', () {
      expect(GraphQLRetry.deservesFallback(serverError(400)), isFalse);
      expect(GraphQLRetry.deservesFallback(serverError(404)), isFalse);
    });

    test('nor is a status the exception did not carry', () {
      expect(
        GraphQLRetry.deservesFallback(
          const ServerException(statusCode: 404),
        ),
        isFalse,
      );
    });
  });

  /// The old behaviour, kept for anything that does put a code in its message.
  group('and by its text when there is no status to read', () {
    test('a message naming a rate limit still arms it', () {
      expect(
        GraphQLRetry.deservesFallback(Exception('HTTP 429 Too Many Requests')),
        isTrue,
      );
    });

    test('an ordinary failure does not', () {
      expect(
        GraphQLRetry.deservesFallback(Exception('Connection closed')),
        isFalse,
      );
    });
  });
}
