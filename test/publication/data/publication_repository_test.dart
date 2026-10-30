import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/utils/graphql_retry.dart';
import 'package:artemis/schema/graphql_query.dart';
import 'package:artemis/schema/graphql_response.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_test/flutter_test.dart';

PublishedVersion _v(String tx, String id,
        {int? height, int time = 0, String? folder}) =>
    PublishedVersion(
      txId: tx,
      publicationId: id,
      driveId: 'd',
      scope: folder == null
          ? const PublicationDriveScope()
          : PublicationFolderScope(folder),
      publishedAt: DateTime.fromMillisecondsSinceEpoch(time * 1000),
      minedAtHeight: height,
    );

void main() {
  test('versions group by publication, newest first: pending, then height', () {
    final publications = groupPublications([
      _v('a1', 'A', height: 10, time: 1),
      _v('a3', 'A', time: 3),
      _v('a2', 'A', height: 20, time: 2),
      _v('b1', 'B', height: 15, time: 1, folder: 'f'),
    ]);
    expect(publications.map((p) => p.id), ['A', 'B']);
    expect(publications.first.versions.map((v) => v.txId), ['a3', 'a2', 'a1']);
    expect(publications.first.earlier.map((v) => v.txId), ['a2', 'a1']);
    expect(publications.last.scope, const PublicationFolderScope('f'));
  });

  test('a tie in a block goes to the later Unix-Time', () {
    final p = groupPublications([
      _v('x', 'A', height: 10, time: 1),
      _v('y', 'A', height: 10, time: 2),
    ]).single;
    expect(p.latest.txId, 'y');
  });

  test('a version with another scope is not a version of that publication', () {
    final p = groupPublications([
      _v('first', 'A', height: 1),
      _v('moved', 'A', height: 2, folder: 'elsewhere'),
    ]).single;
    expect(p.versions.map((v) => v.txId), ['first']);
  });

  group('publicationsOfOwner', () {
    Map<String, dynamic> page({required bool more, int count = 1}) => {
          'transactions': {
            'pageInfo': {'hasNextPage': more},
            'edges': [
              for (var i = 0; i < count; i++)
                {
                  'cursor': 'cursor-$i',
                  'node': {
                    'id': 'NOT_A_PUBLICATION_$i',
                    'owner': {'address': 'OWNER'},
                    'bundledIn': null,
                    'block': null,
                    'tags': <Map<String, String>>[],
                  },
                },
            ],
          },
        };

    PublicationRepository repository(List<Map<String, dynamic>> pages) =>
        PublicationRepository(
          graphQLRetry: _Pages(pages),
          gatewayUrl: () => 'https://turbo-gateway.com',
        );

    test('a file page is found by Publication-File-Id, never by File-Id',
        () async {
      Map<String, dynamic> node(String id, Map<String, String> extra) => {
            'cursor': id,
            'node': {
              'id': id,
              'owner': {'address': 'OWNER'},
              'bundledIn': null,
              'block': null,
              'tags': [
                for (final MapEntry(:key, :value) in {
                  'Entity-Type': 'publication',
                  'Drive-Id': 'drive',
                  'Publication-Id': 'pub-$id',
                  'Unix-Time': '1792800000',
                  ...extra,
                }.entries)
                  {'name': key, 'value': value},
              ],
            },
          };
      final found = await repository([
        {
          'transactions': {
            'pageInfo': {'hasNextPage': false},
            'edges': [
              node('PAGE', {
                'Publication-Scope': 'file',
                'Publication-File-Id': 'file-1',
              }),
              // Unreadable as a file page: no Publication-File-Id.
              node('BAD', {'Publication-Scope': 'file', 'File-Id': 'file-2'}),
              node('DRIVE', {'Publication-Scope': 'drive'}),
            ],
          },
        },
      ]).publicationsOfOwner('OWNER');

      final scopes = {
        for (final p in found['drive']!) p.id: p.scope,
      };
      expect(scopes, {
        'pub-PAGE': const PublicationFileScope('file-1'),
        'pub-DRIVE': const PublicationDriveScope(),
      });
    });

    test('reads every page to the end', () async {
      final found = await repository([page(more: true), page(more: false)])
          .publicationsOfOwner('OWNER');
      expect(found, isEmpty);
    });

    test('an empty page ends the list, whatever hasNextPage says', () async {
      // Some gateways report another page after the last one.
      final found =
          await repository([page(more: true), page(more: true, count: 0)])
              .publicationsOfOwner('OWNER');
      expect(found, isEmpty);
    });

    test('a list cut off at the page cap is a failure, not "none"', () async {
      // Claiming "none" for a drive that was cut off would offer to publish
      // it a second time.
      await expectLater(
        repository(List.filled(25, page(more: true)))
            .publicationsOfOwner('OWNER'),
        throwsA(isA<PublicationReadException>()),
      );
    });
  });
}

/// Answers each GraphQL call with the next page.
class _Pages implements GraphQLRetry {
  _Pages(this._pages);

  final List<Map<String, dynamic>> _pages;
  int _index = 0;

  @override
  Future<GraphQLResponse<T>> execute<T, U extends JsonSerializable>(
    GraphQLQuery<T, U> query, {
    Function(Exception e)? onRetry,
    int maxAttempts = GraphQLRetry.defaultMaxAttempts,
  }) async =>
      GraphQLResponse(data: query.parse(_pages[_index++]));
}
