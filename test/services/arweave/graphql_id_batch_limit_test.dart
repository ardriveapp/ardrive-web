import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/graphql_retry.dart';
import 'package:flutter_test/flutter_test.dart';

/// How many transaction ids may go into one query's `ids` argument.
///
/// Reported from the browser with Goldsky configured as the GraphQL endpoint:
///
///   Too many ids in 'ids' argument: 31 provided, maximum 9 allowed
///
/// The number matters beyond that configuration, which is why it is asserted
/// rather than left as a constant somebody may later "optimise". Every query
/// that chunks ids can be served by Goldsky whether or not it was asked for:
/// [GraphQLRetry] falls back there on a 429 or a 5xx. A batch the fallback
/// cannot accept therefore makes the fallback useless for these queries on
/// every configuration - the sync hits a rate limit, switches to the endpoint
/// that exists to rescue it, and is refused for the shape of the request.
void main() {
  test('a batch fits what the fallback endpoint accepts', () {
    expect(
      maxGraphQLIdsPerQuery,
      lessThanOrEqualTo(9),
      reason: 'Goldsky refuses more than nine, and any of these queries can '
          'land on Goldsky through the fallback',
    );
  });

  test('and the fallback really is the endpoint with that limit', () {
    expect(
      GraphQLRetry.defaultFallbackGraphqlUrl,
      contains('goldsky'),
      reason: 'if the fallback moves, the cap above should be re-derived from '
          'whatever the new one accepts rather than left at nine by accident',
    );
  });

  test('and the batch is still worth batching', () {
    expect(
      maxGraphQLIdsPerQuery,
      greaterThan(1),
      reason: 'one id per request is not a batch, and these run in a loop over '
          'every unconfirmed transaction in a sync',
    );
  });
}
