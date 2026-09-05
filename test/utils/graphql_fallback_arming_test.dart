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

  /// What is worth asking the same endpoint twice.
  ///
  /// `package:retry` retries every exception unless told otherwise, and the
  /// budget is five attempts with growing backoff - so a request that cannot
  /// succeed spent about six seconds failing five times, and delayed the
  /// fallback that might have helped.
  group('a retry has to be able to change the answer', () {
    HttpLinkServerException serverError(int status) => HttpLinkServerException(
          response: http.Response('', status),
          parsedResponse: const gql.Response(response: {}),
        );

    test('a rate limit is about the moment, so it is retried', () {
      expect(GraphQLRetry.worthRetrying(serverError(429)), isTrue);
    });

    test('so is a gateway that fell over', () {
      expect(GraphQLRetry.worthRetrying(serverError(502)), isTrue);
      expect(GraphQLRetry.worthRetrying(serverError(503)), isTrue);
    });

    test('a request the server rejected is not', () {
      expect(
        GraphQLRetry.worthRetrying(serverError(400)),
        isFalse,
        reason: 'the same malformed request fails the same way, five times, '
            'slowly',
      );
      expect(GraphQLRetry.worthRetrying(serverError(404)), isFalse);
    });

    /// This one came back over a *successful* HTTP response: the endpoint read
    /// the question and answered it.
    test('nor is a query the server understood and refused', () {
      expect(
        GraphQLRetry.worthRetrying(GraphQLException(const ['bad field'])),
        isFalse,
      );
    });

    test('but a failure with no status at all still is', () {
      expect(
        GraphQLRetry.worthRetrying(Exception('Connection closed')),
        isTrue,
        reason: 'a dropped socket is exactly what a retry is for',
      );
    });
  });
}
