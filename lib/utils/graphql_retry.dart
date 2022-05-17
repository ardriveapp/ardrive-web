import 'package:artemis/client.dart';
import 'package:artemis/schema/graphql_query.dart';
import 'package:artemis/schema/graphql_response.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:retry/retry.dart';

/// Retry every GraphQL query for `ArtemisClient`
class GraphQLRetry {
  GraphQLRetry(this._client);

  final ArtemisClient _client;

  Future<GraphQLResponse<T>> execute<T, U extends JsonSerializable>(
      GraphQLQuery<T, U> query,
      {Function(Exception e)? onRetry}) async {
    try {
      final queryResponse = retry(
        () async => await _client.execute(query),
        onRetry: (exception) {
          onRetry?.call(exception);
          print(
              'Retrying for query ${query.toString()} on Exception ${exception.toString()}');
        },
      );

      return queryResponse;
    } catch (e) {
      late Object exception;
      if (e.toString().contains('FormatException')) {
        exception = const FormatException('Returned data is not a valid JSON.');
      } else {
        exception = e;
      }
      print(
          'Fatal error while querying ${query.operationName}. Exceed the number of retries. Exception ${exception.toString()}');
      throw exception;
    }
  }
}
