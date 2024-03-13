void main() {
  // TODO: Fix this test after implementing the fakeNodesStream emiting DriveEntityHistoryTransactionModel
  // group('GQLDriveHistory class', () {
  //   final arweave = MockArweaveService();

  //   // TODO: test the getter for the data when implemented

  //   setUp(() {
  //     when(
  //       () => arweave.getSegmentedTransactionsFromDrive(
  //         'DRIVE_ID',
  //         minBlockHeight: captureAny(named: 'minBlockHeight'),
  //         maxBlockHeight: captureAny(named: 'maxBlockHeight'),
  //         ownerAddress: 'owner',
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

  //     when(() => arweave.getOwnerForDriveEntityWithId('DRIVE_ID')).thenAnswer(
  //       (invocation) => Future.value('owner'),
  //     );
  //   });

  //   test('getStreamForIndex returns a valid stream of nodes', () async {
  //     GQLDriveHistory gqlDriveHistory = GQLDriveHistory(
  //       arweave: arweave,
  //       driveId: 'DRIVE_ID',
  //       subRanges: HeightRange(rangeSegments: [Range(start: 0, end: 10)]),
  //       ownerAddress: 'owner',
  //     );
  //     expect(gqlDriveHistory.subRanges.rangeSegments.length, 1);
  //     expect(gqlDriveHistory.currentIndex, -1);
  //     Stream stream = gqlDriveHistory.getNextStream();
  //     expect(gqlDriveHistory.currentIndex, 0);
  //     expect(await countStreamItems(stream), 11);

  //     expect(
  //       () => gqlDriveHistory.getNextStream(),
  //       throwsA(isA<SubRangeIndexOverflow>()),
  //     );

  //     gqlDriveHistory = GQLDriveHistory(
  //       arweave: arweave,
  //       driveId: 'DRIVE_ID',
  //       subRanges: HeightRange(rangeSegments: [
  //         Range(start: 0, end: 10),
  //         Range(start: 20, end: 30)
  //       ]),
  //       ownerAddress: 'owner',
  //     );
  //     expect(gqlDriveHistory.subRanges.rangeSegments.length, 2);
  //     expect(gqlDriveHistory.currentIndex, -1);
  //     stream = gqlDriveHistory.getNextStream();
  //     expect(gqlDriveHistory.currentIndex, 0);
  //     expect(await countStreamItems(stream), 11);
  //     stream = gqlDriveHistory.getNextStream();
  //     expect(gqlDriveHistory.currentIndex, 1);
  //     expect(await countStreamItems(stream), 11);

  //     expect(
  //       () => gqlDriveHistory.getNextStream(),
  //       throwsA(isA<SubRangeIndexOverflow>()),
  //     );
  //   });
  // });
}
