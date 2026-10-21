import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/snapshot_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

/// A snapshot read from the network, as bytes, the way sync reads one - not
/// handed in as a string, which is how the snapshot tests beside this one
/// skip the step that went wrong.
void main() {
  const driveId = 'utf8-drive';
  final names = [
    'Talks — 2024',
    'Café',
    '日本の写真',
    'Trip 🏔️',
  ];

  Map<String, dynamic> gqlNode(int height) => {
        'id': 'tx-$height',
        'bundledIn': {'id': 'bundle'},
        'owner': {'address': 'owner'},
        'tags': [],
        'block': {'height': height, 'timestamp': height * 100},
      };

  SnapshotItem snapshotWith(
    ArweaveService arweave,
    String snapshotTxId,
    Range range,
  ) =>
      SnapshotItem.fromGQLNode(
        node:
            SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
                .fromJson({
          'id': snapshotTxId,
          'bundledIn': {'id': 'bundle'},
          'owner': {'address': 'owner'},
          'tags': [
            {'name': 'Block-Start', 'value': '${range.start}'},
            {'name': 'Block-End', 'value': '${range.end}'},
            {'name': 'Drive-Id', 'value': driveId},
          ],
          'block': {'height': 100, 'timestamp': 1},
        }),
        subRanges: HeightRange(rangeSegments: [range]),
        arweave: arweave,
      );

  Future<void> drain(SnapshotItem item) async {
    await for (final _ in item.getNextStream()) {}
  }

  test('names past ASCII come out of a snapshot exactly as they went in',
      () async {
    final arweave = MockArweaveService();
    final range = Range(start: 0, end: names.length - 1);
    final snapshot = utf8.encode(jsonEncode({
      'txSnapshots': [
        for (var i = 0; i < names.length; i++)
          {
            'gqlNode': gqlNode(i),
            'jsonMetadata': jsonEncode({'name': names[i]}),
          },
      ],
    }));
    when(() => arweave.getEntityDataFromNetwork(
          txId: 'snapshot-a',
          largeBody: any(named: 'largeBody'),
        )).thenAnswer((_) async => Uint8List.fromList(snapshot));

    await drain(snapshotWith(arweave, 'snapshot-a', range));

    for (var i = 0; i < names.length; i++) {
      final stored = await SnapshotItemOnChain.getDataForTxId(driveId, 'tx-$i');
      expect(jsonDecode(utf8.decode(stored!))['name'], names[i]);
    }
  });

  test('a snapshot written already damaged is repaired as it is read',
      () async {
    // Another tool that read UTF-8 as Latin-1, then wrote what it read.
    String damaged(String text) => String.fromCharCodes(utf8.encode(text));

    final arweave = MockArweaveService();
    final range = Range(start: 10, end: 10 + names.length - 1);
    final snapshot = utf8.encode(jsonEncode({
      'txSnapshots': [
        for (var i = 0; i < names.length; i++)
          {
            'gqlNode': gqlNode(10 + i),
            'jsonMetadata': damaged(jsonEncode({'name': names[i]})),
          },
      ],
    }));
    when(() => arweave.getEntityDataFromNetwork(
          txId: 'snapshot-b',
          largeBody: any(named: 'largeBody'),
        )).thenAnswer((_) async => Uint8List.fromList(snapshot));

    await drain(snapshotWith(arweave, 'snapshot-b', range));

    for (var i = 0; i < names.length; i++) {
      final stored =
          await SnapshotItemOnChain.getDataForTxId(driveId, 'tx-${10 + i}');
      expect(jsonDecode(utf8.decode(stored!))['name'], names[i]);
    }
  });
}
