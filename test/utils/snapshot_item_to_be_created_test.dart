import 'dart:convert';

import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/snapshot_item_to_be_created.dart';
import 'package:flutter_test/flutter_test.dart';

import 'snapshot_test_helpers.dart';

void main() {
  group('SnapshotItemToBeCreated class', () {
    group('getSnapshotData method', () {
      test('returns the correct data for an empty set', () async {
        final snapshotItem = SnapshotItemToBeCreated(
          driveId: 'DRIVE_ID',
          blockStart: 0,
          blockEnd: 10,
          subRanges: HeightRange(rangeSegments: [Range(start: 0, end: 10)]),
          source: const Stream.empty(),
          jsonMetadataOfTxId: (txId) async => '{"name":"$txId"}',
        );

        final snapshotData = (await snapshotItem
                .getSnapshotData()
                .map(utf8.decoder.convert)
                .toList())
            .join();

        expect(snapshotData, '{"txSnapshots":[]}');
      });

      test('returns the correct data for a single transaction', () async {
        final snapshotItem = SnapshotItemToBeCreated(
          driveId: 'DRIVE_ID',
          blockStart: 0,
          blockEnd: 10,
          subRanges: HeightRange(rangeSegments: [Range(start: 0, end: 10)]),
          source: fakeNodesStream(Range(start: 8, end: 8)),
          jsonMetadataOfTxId: (txId) async => '{"name":"$txId"}',
        );

        final snapshotData = (await snapshotItem
                .getSnapshotData()
                .map(utf8.decoder.convert)
                .toList())
            .join();

        expect(
          snapshotData,
          '{"txSnapshots":[{"gqlNode":{"id":"tx-8","owner":{"address":"1234567890"},"bundledIn":{"id":"ASDASDASDASDASDASD"},"block":{"height":8,"timestamp":800},"tags":[]},"jsonMetadata":"{\\"name\\":\\"tx-8\\"}"}]}',
        );
      });

      test(
          'the returned data won\'t contain metadatadata of other snapshots, but only the gql node',
          () async {
        final snapshotItem = SnapshotItemToBeCreated(
          driveId: 'DRIVE_ID',
          blockStart: 0,
          blockEnd: 10,
          subRanges: HeightRange(rangeSegments: [Range(start: 0, end: 10)]),
          source: Stream.fromIterable(
            [
              DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
                  .fromJson(
                {
                  'id': 'tx-7',
                  'bundledIn': {'id': 'ASDASDASDASDASDASD'},
                  'owner': {'address': '1234567890'},
                  'tags': [
                    {'name': 'Entity-Type', 'value': 'snapshot'},
                  ],
                  'block': {
                    'height': 7,
                    'timestamp': 700,
                  }
                },
              ),
            ],
          ),
          jsonMetadataOfTxId: (txId) async => '{"name":"tx-$txId"}',
        );

        final snapshotData = (await snapshotItem
                .getSnapshotData()
                .map(utf8.decoder.convert)
                .toList())
            .join();

        expect(
          snapshotData,
          '{"txSnapshots":[{"gqlNode":{"id":"tx-7","owner":{"address":"1234567890"},"bundledIn":{"id":"ASDASDASDASDASDASD"},"block":{"height":7,"timestamp":700},"tags":[{"name":"Entity-Type","value":"snapshot"}]},"jsonMetadata":""}]}',
        );
      });
    });
  });
}
