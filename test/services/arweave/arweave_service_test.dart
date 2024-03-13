const gatewayUrl = 'https://arweave.net';
void main() {
  // TODO: Fix this test after implementing the fakeNodesStream emiting DriveEntityHistoryTransactionModel
  // group('ArweaveService class', () {
  //   const knownFileId = 'ffffffff-0000-0000-0000-ffffffffffff';
  //   const unknownFileId = 'aaaaaaaa-0000-0000-0000-ffffffffffff';

  //   AppPlatform.setMockPlatform(platform: SystemPlatform.unknown);

  //   final arweave = MockArweaveService();

  //   setUp(() {
  //     when(
  //       () => arweave.getSegmentedTransactionsFromDrive(
  //         'DRIVE_ID',
  //         minBlockHeight: captureAny(named: 'minBlockHeight'),
  //         maxBlockHeight: captureAny(named: 'maxBlockHeight'),
  //         ownerAddress: any(named: 'ownerAddress'),
  //       ),
  //     ).thenAnswer(
  //       (invocation) => fakeNodesStream(
  //         Range(
  //           start: invocation.namedArguments[const Symbol('minBlockHeight')],
  //           end: invocation.namedArguments[const Symbol('maxBlockHeight')],
  //         ),
  //       )
  //           .map(
  //             (event) =>
  //                 DriveEntityHistory$Query$TransactionConnection$TransactionEdge()
  //                   ..node = event
  //                   ..cursor = 'mi cursor',
  //           )
  //           .map((event) => [event]),
  //     );
  //     when(() => arweave.getOwnerForDriveEntityWithId(any())).thenAnswer(
  //       (invocation) => Future.value('owner'),
  //     );
  //     when(() => arweave.getAllFileEntitiesWithId(any())).thenAnswer(
  //       (invocation) => Future.value(),
  //     );
  //     when(() => arweave.getAllFileEntitiesWithId(knownFileId)).thenAnswer(
  //       (invocation) => Future.value([FileEntity()]),
  //     );
  //   });

  //   group('getAllFileEntitiesWithId method', () {
  //     test('returns all the file entities for a known file id', () async {
  //       final fileEntities =
  //           await arweave.getAllFileEntitiesWithId(knownFileId);
  //       expect(fileEntities?.length, equals(1));
  //     });

  //     test('returns null for non-existant file id', () async {
  //       final fileEntities = await arweave.getAllFileEntitiesWithId(
  //         unknownFileId,
  //       );
  //       expect(fileEntities, equals(null));
  //     });
  //   });
  // });
}
