import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/snapshot_entity.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

typedef DriveHistoryTransaction
    = DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SnapshotEntity class', () {
    setUp(() {
      // mocks PackageInfo
      PackageInfo.setMockInitialValues(
        appName: 'appName',
        packageName: 'packageName',
        version: '1.2.3',
        buildNumber: 'buildNumber',
        buildSignature: 'buildSignature',
      );
    });

    group('constructor', () {
      late DriveHistoryTransaction fakeTransaction;
      late DriveHistoryTransaction fakeInvalidTransaction;
      final fakeTimestamp = DateTime.fromMillisecondsSinceEpoch(1234567890000);

      setUp(() {
        fakeTransaction = DriveHistoryTransaction.fromJson({
          'id': 'FAKE TX ID',
          'owner': {
            'address': 'FAKE WALLET ADDRESS',
          },
          'tags': [
            {'name': EntityTag.snapshotId, 'value': 'FAKE SNAPSHOT ID'},
            {'name': EntityTag.entityType, 'value': EntityType.snapshot},
            {'name': EntityTag.driveId, 'value': 'FAKE DRIVE ID'},
            {'name': EntityTag.blockStart, 'value': '0'},
            {'name': EntityTag.blockEnd, 'value': '100'},
            {'name': EntityTag.dataStart, 'value': '20'},
            {'name': EntityTag.dataEnd, 'value': '98'},
            {
              'name': EntityTag.unixTime,
              'value': '${fakeTimestamp.millisecondsSinceEpoch ~/ 1000}'
            }
          ],
        });

        fakeInvalidTransaction = DriveHistoryTransaction.fromJson({
          'id': 'FAKE TX ID',
          'owner': {
            'address': 'FAKE WALLET ADDRESS',
          },
          'tags': [
            {'name': EntityTag.snapshotId, 'value': 'FAKE SNAPSHOT ID'},
          ],
        });
      });

      test('can be instantiated from a valid transaction', () async {
        final snapshotEntity = await SnapshotEntity.fromTransaction(
          fakeTransaction,
          Uint8List(0),
        );

        expect(snapshotEntity.id, 'FAKE SNAPSHOT ID');
        expect(snapshotEntity.driveId, 'FAKE DRIVE ID');
        expect(snapshotEntity.blockStart, 0);
        expect(snapshotEntity.blockEnd, 100);
        expect(snapshotEntity.dataStart, 20);
        expect(snapshotEntity.dataEnd, 98);
        expect(snapshotEntity.txId, 'FAKE TX ID');
        expect(snapshotEntity.ownerAddress, 'FAKE WALLET ADDRESS');
        expect(snapshotEntity.createdAt, fakeTimestamp);
      });

      test('throws the expected error when there\'s an error parsing it', () {
        expect(
          () => SnapshotEntity.fromTransaction(
            fakeInvalidTransaction,
            Uint8List(0),
          ),
          throwsA(isA<EntityTransactionParseException>()),
        );
      });
    });

    group('addEntityTagsToTransaction method', () {
      test('adds the expected tags to the transaction', () {
        final snapshotEntity = SnapshotEntity(
          id: 'FAKE SNAPSHOT ID',
          driveId: 'FAKE DRIVE ID',
          blockStart: 0,
          blockEnd: 100,
          dataStart: 20,
          dataEnd: 98,
        );
        final transaction = Transaction();

        snapshotEntity.addEntityTagsToTransaction(transaction);

        expect(transaction.tags.length, 8);
        expect(decodeBase64ToString(transaction.tags[0].name), equals('ArFS'));
        expect(decodeBase64ToString(transaction.tags[0].value), equals('0.11'));
        expect(decodeBase64ToString(transaction.tags[1].name),
            equals('Entity-Type'));
        expect(decodeBase64ToString(transaction.tags[1].value),
            equals('snapshot'));
        expect(
            decodeBase64ToString(transaction.tags[2].name), equals('Drive-Id'));
        expect(decodeBase64ToString(transaction.tags[2].value),
            equals('FAKE DRIVE ID'));
        expect(decodeBase64ToString(transaction.tags[3].name),
            equals('Snapshot-Id'));
        expect(decodeBase64ToString(transaction.tags[3].value),
            equals('FAKE SNAPSHOT ID'));
        expect(decodeBase64ToString(transaction.tags[4].name),
            equals('Block-Start'));
        expect(decodeBase64ToString(transaction.tags[4].value), equals('0'));
        expect(decodeBase64ToString(transaction.tags[5].name),
            equals('Block-End'));
        expect(decodeBase64ToString(transaction.tags[5].value), equals('100'));
        expect(decodeBase64ToString(transaction.tags[6].name),
            equals('Data-Start'));
        expect(decodeBase64ToString(transaction.tags[6].value), equals('20'));
      });
    });

    group('asTransaction method', () {
      test('throws if the key is passed', () {
        final snapshotEntity = SnapshotEntity(
          id: 'FAKE SNAPSHOT ID',
          driveId: 'FAKE DRIVE ID',
          blockStart: 0,
          blockEnd: 100,
          dataStart: 20,
          dataEnd: 98,
        );

        expect(
            () => snapshotEntity.asTransaction(key: SecretKey([])),
            throwsA(
              isA<UnsupportedError>(),
            ));
      });

      test('returns a valid TX from a healthy snapshot entity', () async {
        final snapshotEntity = SnapshotEntity(
          id: 'FAKE SNAPSHOT ID',
          driveId: 'FAKE DRIVE ID',
          blockStart: 0,
          blockEnd: 100,
          dataStart: 20,
          dataEnd: 98,
          data: Uint8List(0),
        );

        final transaction = await snapshotEntity.asTransaction();

        expect(transaction, isA<Transaction>());
        expect(transaction.tags.length, 13);

        expect(
          decodeBase64ToString(transaction.tags[0].name),
          equals('Content-Type'),
        );
        expect(
          decodeBase64ToString(transaction.tags[0].value),
          equals('application/json'),
        );
        expect(decodeBase64ToString(transaction.tags[1].name), equals('ArFS'));
        expect(decodeBase64ToString(transaction.tags[1].value), equals('0.11'));
        expect(
          decodeBase64ToString(transaction.tags[2].name),
          equals('Entity-Type'),
        );
        expect(
          decodeBase64ToString(transaction.tags[2].value),
          equals('snapshot'),
        );
        expect(
          decodeBase64ToString(transaction.tags[3].name),
          equals('Drive-Id'),
        );
        expect(
          decodeBase64ToString(transaction.tags[3].value),
          equals('FAKE DRIVE ID'),
        );
        expect(
          decodeBase64ToString(transaction.tags[4].name),
          equals('Snapshot-Id'),
        );
        expect(
          decodeBase64ToString(transaction.tags[4].value),
          equals('FAKE SNAPSHOT ID'),
        );
        expect(
          decodeBase64ToString(transaction.tags[5].name),
          equals('Block-Start'),
        );
        expect(
          decodeBase64ToString(transaction.tags[5].value),
          equals('0'),
        );
        expect(
          decodeBase64ToString(transaction.tags[6].name),
          equals('Block-End'),
        );
        expect(
          decodeBase64ToString(transaction.tags[6].value),
          equals('100'),
        );
        expect(
          decodeBase64ToString(transaction.tags[7].name),
          equals('Data-Start'),
        );
        expect(
          decodeBase64ToString(transaction.tags[7].value),
          equals('20'),
        );
        expect(
          decodeBase64ToString(transaction.tags[8].name),
          equals('Data-End'),
        );
        expect(
          decodeBase64ToString(transaction.tags[8].value),
          equals('98'),
        );
        expect(
          decodeBase64ToString(transaction.tags[9].name),
          equals('App-Name'),
        );
        expect(
          decodeBase64ToString(transaction.tags[9].value),
          equals('ArDrive-App'),
        );
        expect(
          decodeBase64ToString(transaction.tags[10].name),
          equals('App-Platform'),
        );
        expect(
          decodeBase64ToString(transaction.tags[10].value),
          equals('unknown'),
        );
        expect(
          decodeBase64ToString(transaction.tags[11].name),
          equals('App-Version'),
        );
        expect(
          decodeBase64ToString(transaction.tags[11].value),
          equals('1.2.3'),
        );
      });
    });
  });
}
