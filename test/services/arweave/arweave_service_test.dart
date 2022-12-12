import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';
import '../../utils/snapshot_item_test.dart';

const gatewayUrl = 'https://arweave.net';
void main() {
  group('ArweaveService class', () {
    const knownFileId = 'ffffffff-0000-0000-0000-ffffffffffff';
    const unknownFileId = 'aaaaaaaa-0000-0000-0000-ffffffffffff';

    //TODO Create and inject mock artemis client
    AppPlatform.setMockPlatform(platform: SystemPlatform.unknown);

    final arweave = MockArweaveService();

    setUp(() {
      when(
        () => arweave.getSegmentedTransactionsFromDrive(
          'DRIVE_ID',
          minBlockHeight: captureAny(named: 'minBlockHeight'),
          maxBlockHeight: captureAny(named: 'maxBlockHeight'),
        ),
      ).thenAnswer(
        (invocation) => fakeNodesStream(
          Range(
            start: invocation.namedArguments[const Symbol('minBlockHeight')],
            end: invocation.namedArguments[const Symbol('maxBlockHeight')],
          ),
        )
            .map(
              (event) =>
                  DriveEntityHistory$Query$TransactionConnection$TransactionEdge()
                    ..node = event
                    ..cursor = 'mi cursor',
            )
            .map((event) => [event]),
      );
      // when(() => arweave.getAllTransactionsFromDrive('DRIVE_ID'));

      when(() => arweave.getAllFileEntitiesWithId(any())).thenAnswer(
        (invocation) => Future.value(),
      );
      when(() => arweave.getAllFileEntitiesWithId(knownFileId)).thenAnswer(
        (invocation) => Future.value([FileEntity()]),
      );
    });

    group('getAllTransactionsFromDrive method', () {
      test('calls getAllTransactionsFromDrive once', () async {
        arweave.getAllTransactionsFromDrive('DRIVE_ID', lastBlockHeight: 10);
        verify(() => arweave.getSegmentedTransactionsFromDrive('DRIVE_ID'))
            .called(1);
      },
          skip:
              'Cannot stub a single method to verify that the actual method gets called once');
    });

    group('getAllFileEntittiesWithId method', () {
      test('returns all the file entities for a known file id', () async {
        final fileEntities =
            await arweave.getAllFileEntitiesWithId(knownFileId);
        expect(fileEntities?.length, equals(1));
      });

      test('returns null for non-existant file id', () async {
        final fileEntities = await arweave.getAllFileEntitiesWithId(
          unknownFileId,
        );
        expect(fileEntities, equals(null));
      });
    });
  });
}
