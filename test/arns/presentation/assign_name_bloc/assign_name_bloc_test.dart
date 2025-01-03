// import 'package:ardrive/arns/domain/arns_repository.dart';
// import 'package:ardrive/arns/presentation/assign_name_bloc/assign_name_bloc.dart';
// import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
// import 'package:ario_sdk/ario_sdk.dart';
// import 'package:bloc_test/bloc_test.dart';
// import 'package:flutter_test/flutter_test.dart';
// import 'package:mocktail/mocktail.dart';

// import '../../../test_utils/utils.dart';

// class MockARNSRepository extends Mock implements ARNSRepository {}

// class MockFileDataTableItem extends Mock implements FileDataTableItem {}

// void main() {
//   setUpAll(() {
//     registerFallbackValue(const ARNSUndername(
//       name: 'test_undername',
//       domain: 'test.ar',
//       record: ARNSRecord(transactionId: 'test_tx_id', ttlSeconds: 3600),
//     ));
//     registerFallbackValue(
//         const ANTRecord(domain: 'test.ar', processId: 'test_process_id'));
//   });

//   group('AssignNameBloc', () {
//     late AssignNameBloc assignNameBloc;
//     late MockARNSRepository mockArnsRepository;
//     late MockArDriveAuth mockAuth;
//     late MockFileDataTableItem mockFileDataTableItem;

//     setUp(() {
//       mockArnsRepository = MockARNSRepository();
//       mockAuth = MockArDriveAuth();
//       mockFileDataTableItem = MockFileDataTableItem();

//       assignNameBloc = AssignNameBloc(
//         auth: mockAuth,
//         fileDataTableItem: mockFileDataTableItem,
//         arnsRepository: mockArnsRepository,
//       );
//     });

//     tearDown(() {
//       assignNameBloc.close();
//     });

//     group('LoadNames', () {
//       test('emits [LoadingNames, NamesLoaded] when LoadNames is added',
//           () async {
//         // Arrange
//         const walletAddress = 'test_wallet_address';
//         final antRecords = [
//           const ANTRecord(domain: 'test1.ar', processId: 'process1'),
//           const ANTRecord(domain: 'test2.ar', processId: 'process2'),
//         ];

//         when(() => mockAuth.getWalletAddress())
//             .thenAnswer((_) async => walletAddress);
//         when(() => mockArnsRepository.getAntRecordsForWallet(walletAddress))
//             .thenAnswer((_) async => antRecords);

//         // Act
//         assignNameBloc.add(const LoadNames());

//         // Assert
//         await expectLater(
//           assignNameBloc.stream,
//           emitsInOrder([
//             isA<LoadingNames>(),
//             isA<NamesLoaded>()
//                 .having((state) => state.names, 'names', antRecords),
//           ]),
//         );

//         verify(() => mockAuth.getWalletAddress()).called(1);
//         verify(() => mockArnsRepository.getAntRecordsForWallet(
//               walletAddress,
//             )).called(1);
//       });

//       test(
//           'emits [LoadingNames, AssignNameEmptyState] when LoadNames is added and no names are returned',
//           () async {
//         // Arrange
//         const walletAddress = 'test_wallet_address';
//         final antRecords = <ANTRecord>[];

//         when(() => mockAuth.getWalletAddress())
//             .thenAnswer((_) async => walletAddress);
//         when(() => mockArnsRepository.getAntRecordsForWallet(walletAddress))
//             .thenAnswer((_) async => antRecords);

//         // Act
//         assignNameBloc.add(const LoadNames());

//         // Assert
//         await expectLater(
//           assignNameBloc.stream,
//           emitsInOrder([
//             isA<LoadingNames>(),
//             isA<AssignNameEmptyState>(),
//           ]),
//         );

//         verify(() => mockAuth.getWalletAddress()).called(1);
//         verify(() => mockArnsRepository.getAntRecordsForWallet(
//               walletAddress,
//             )).called(1);
//       });

//       test('emits [LoadingNames, LoadingNamesFailed] when LoadNames is added',
//           () async {
//         // Arrange
//         const walletAddress = 'test_wallet_address';

//         when(() => mockAuth.getWalletAddress())
//             .thenAnswer((_) async => walletAddress);
//         when(() => mockArnsRepository.getAntRecordsForWallet(walletAddress,
//             update: true)).thenThrow(StateError('Test error'));

//         // Act
//         assignNameBloc.add(const LoadNames());

//         // Assert
//         await expectLater(
//           assignNameBloc.stream,
//           emitsInOrder([
//             isA<LoadingNames>(),
//             isA<LoadingNamesFailed>(),
//           ]),
//         );
//       });
//     });

//     group('SelectName', () {
//       test('emits NamesLoaded with selected name when SelectName is added',
//           () async {
//         // Arrange
//         final antRecords = [
//           const ANTRecord(domain: 'domain1.ar', processId: 'process1'),
//           const ANTRecord(domain: 'domain2.ar', processId: 'process2'),
//         ];
//         final selectedName = antRecords[0];

//         assignNameBloc.emit(NamesLoaded(names: antRecords));

//         // Act
//         assignNameBloc.add(SelectName(selectedName));

//         // Assert
//         await expectLater(
//           assignNameBloc.stream,
//           emits(
//             isA<NamesLoaded>()
//                 .having((state) => state.names, 'names', antRecords)
//                 .having((state) => state.selectedName, 'selectedName',
//                     selectedName),
//           ),
//         );
//       });

//       test(
//           'emits NamesLoaded when SelectName is added in UndernamesLoaded state',
//           () async {
//         // Arrange
//         final antRecords = [
//           const ANTRecord(domain: 'domain1.ar', processId: 'process1'),
//           const ANTRecord(domain: 'domain2.ar', processId: 'process2'),
//         ];
//         final selectedName = antRecords[1];
//         final undernames = [
//           const ARNSUndername(
//               name: 'undername1',
//               domain: 'domain1.ar',
//               record: ARNSRecord(transactionId: 'tx1', ttlSeconds: 3600)),
//         ];

//         assignNameBloc.emit(UndernamesLoaded(
//           names: antRecords,
//           selectedName: antRecords[0],
//           undernames: undernames,
//           selectedUndername: null,
//         ));

//         // Act
//         assignNameBloc.add(SelectName(selectedName));

//         // Assert
//         await expectLater(
//           assignNameBloc.stream,
//           emits(
//             isA<NamesLoaded>()
//                 .having((state) => state.names, 'names', antRecords)
//                 .having((state) => state.selectedName, 'selectedName',
//                     selectedName),
//           ),
//         );
//       });
//     });

//     group('LoadUndernames', () {
//       test(
//           'emits LoadingUndernames and then UndernamesLoaded when LoadUndernames is added',
//           () async {
//         // Arrange
//         final antRecords = [
//           const ANTRecord(domain: 'domain1.ar', processId: 'process1'),
//           const ANTRecord(domain: 'domain2.ar', processId: 'process2'),
//         ];
//         final selectedName = antRecords[0];
//         final undernames = [
//           const ARNSUndername(
//             name: 'undername1',
//             domain: 'domain1.ar',
//             record: ARNSRecord(transactionId: 'tx1', ttlSeconds: 3600),
//           ),
//           const ARNSUndername(
//             name: 'undername2',
//             domain: 'domain1.ar',
//             record: ARNSRecord(transactionId: 'tx2', ttlSeconds: 3600),
//           ),
//         ];

//         when(() => mockArnsRepository.getARNSUndernames(selectedName))
//             .thenAnswer((_) async => undernames);

//         assignNameBloc.add(SelectName(selectedName));
//         assignNameBloc
//             .emit(NamesLoaded(names: antRecords, selectedName: selectedName));

//         // Act
//         assignNameBloc.add(const LoadUndernames());

//         // Assert
//         await expectLater(
//           assignNameBloc.stream,
//           emitsInOrder([
//             isA<LoadingUndernames>(),
//             isA<UndernamesLoaded>()
//                 .having((state) => state.names, 'names', antRecords)
//                 .having(
//                     (state) => state.selectedName, 'selectedName', selectedName)
//                 .having((state) => state.undernames, 'undernames', undernames)
//                 .having((state) => state.selectedUndername, 'selectedUndername',
//                     null),
//           ]),
//         );

//         verify(() => mockArnsRepository.getARNSUndernames(selectedName))
//             .called(1);
//       });
//     });

//     group('SelectUndername', () {
//       test(
//           'emits UndernamesLoaded with selected undername when SelectUndername is added',
//           () async {
//         // Arrange
//         final antRecords = [
//           const ANTRecord(domain: 'domain1.ar', processId: 'process1'),
//           const ANTRecord(domain: 'domain2.ar', processId: 'process2'),
//         ];
//         final selectedName = antRecords[0];
//         final undernames = [
//           const ARNSUndername(
//             name: 'undername1',
//             domain: 'domain1.ar',
//             record: ARNSRecord(transactionId: 'tx1', ttlSeconds: 3600),
//           ),
//           const ARNSUndername(
//             name: 'undername2',
//             domain: 'domain1.ar',
//             record: ARNSRecord(transactionId: 'tx2', ttlSeconds: 3600),
//           ),
//         ];
//         final selectedUndername = undernames[0];

//         assignNameBloc.emit(UndernamesLoaded(
//           names: antRecords,
//           selectedName: selectedName,
//           undernames: undernames,
//           selectedUndername: null,
//         ));

//         // Act
//         assignNameBloc.add(SelectUndername(undername: selectedUndername));

//         // Assert
//         await expectLater(
//           assignNameBloc.stream,
//           emits(
//             isA<UndernamesLoaded>()
//                 .having((state) => state.names, 'names', antRecords)
//                 .having(
//                     (state) => state.selectedName, 'selectedName', selectedName)
//                 .having((state) => state.undernames, 'undernames', undernames)
//                 .having((state) => state.selectedUndername, 'selectedUndername',
//                     selectedUndername),
//           ),
//         );
//       });
//     });

//     group('ConfirmSelection', () {
//       blocTest<AssignNameBloc, AssignNameState>(
//         'emits [ConfirmingSelection, SelectionConfirmed] when ConfirmSelection is added',
//         build: () {
//           when(() => mockFileDataTableItem.dataTxId)
//               .thenReturn('test_data_tx_id');
//           when(() => mockFileDataTableItem.fileId).thenReturn('test_file_id');
//           when(() => mockFileDataTableItem.driveId).thenReturn('test_drive_id');
//           final antRecords = [
//             const ANTRecord(domain: 'test1.ar', processId: 'process1'),
//             const ANTRecord(domain: 'test2.ar', processId: 'process2'),
//           ];

//           const walletAddress = 'test_wallet_address';

//           when(() => mockAuth.getWalletAddress())
//               .thenAnswer((_) async => walletAddress);
//           when(() => mockArnsRepository.getAntRecordsForWallet(walletAddress))
//               .thenAnswer((_) async => antRecords);
//           when(() => mockArnsRepository.setUndernamesToFile(
//                 undername: any(named: 'undername'),
//                 fileId: any(named: 'fileId'),
//                 driveId: any(named: 'driveId'),
//                 processId: any(named: 'processId'),
//               )).thenAnswer((_) async {});
//           when(() => mockArnsRepository.getARNSUndernames(any())).thenAnswer(
//             (_) async => [
//               const ARNSUndername(
//                 name: 'undername',
//                 domain: 'domain',
//                 record:
//                     ARNSRecord(transactionId: 'test_tx_id', ttlSeconds: 3600),
//               )
//             ],
//           );
//           return assignNameBloc;
//         },
//         act: (bloc) {
//           bloc.add(const LoadNames());
//           bloc.add(
//               const SelectName(ANTRecord(domain: 'domain', processId: 'process_id')));
//           bloc.add(const LoadUndernames());
//           bloc.add(const SelectUndername(
//             undername: ARNSUndername(
//               name: 'undername',
//               domain: 'domain',
//               record: ARNSRecord(transactionId: 'test_tx_id', ttlSeconds: 3600),
//             ),
//           ));
//           bloc.add(ConfirmSelectionAndUpload());
//         },
//         expect: () => [
//           isA<LoadingNames>(),
//           isA<NamesLoaded>(),
//           isA<LoadingUndernames>(),
//           isA<UndernamesLoaded>(),
//           isA<UndernamesLoaded>(),
//           isA<ConfirmingSelection>(),
//           isA<NameAssignedWithSuccess>()
//               .having((state) => state.address, 'address',
//                   'https://undername_domain.ar-io.dev')
//               .having((state) => state.arAddress, 'arAddress',
//                   'ar://undername_domain'),
//         ],
//         verify: (_) {
//           verify(() => mockArnsRepository.setUndernamesToFile(
//                 undername: any(named: 'undername'),
//                 fileId: any(named: 'fileId'),
//                 driveId: any(named: 'driveId'),
//                 processId: any(named: 'processId'),
//               )).called(1);
//         },
//       );
//     });

//     blocTest<AssignNameBloc, AssignNameState>(
//       'emits [ConfirmingSelection, SelectionFailed] when ConfirmSelection is added',
//       build: () {
//         when(() => mockFileDataTableItem.dataTxId)
//             .thenReturn('test_data_tx_id');
//         when(() => mockFileDataTableItem.fileId).thenReturn('test_file_id');
//         when(() => mockFileDataTableItem.driveId).thenReturn('test_drive_id');
//         final antRecords = [
//           const ANTRecord(domain: 'test1.ar', processId: 'process1'),
//           const ANTRecord(domain: 'test2.ar', processId: 'process2'),
//         ];

//         const walletAddress = 'test_wallet_address';

//         when(() => mockAuth.getWalletAddress())
//             .thenAnswer((_) async => walletAddress);
//         when(() => mockArnsRepository.getAntRecordsForWallet(
//               walletAddress,
//             )).thenAnswer((_) async => antRecords);

//         /// FAILED CALL
//         when(() => mockArnsRepository.setUndernamesToFile(
//               undername: any(named: 'undername'),
//               fileId: any(named: 'fileId'),
//               driveId: any(named: 'driveId'),
//               processId: any(named: 'processId'),
//             )).thenThrow(StateError('Test error'));
//         when(() => mockArnsRepository.getARNSUndernames(any())).thenAnswer(
//           (_) async => [
//             const ARNSUndername(
//               name: 'undername',
//               domain: 'domain',
//               record: ARNSRecord(transactionId: 'test_tx_id', ttlSeconds: 3600),
//             )
//           ],
//         );
//         return assignNameBloc;
//       },
//       act: (bloc) {
//         bloc.add(const LoadNames());
//         bloc.add(
//             const SelectName(ANTRecord(domain: 'domain', processId: 'process_id')));
//         bloc.add(const LoadUndernames());
//         bloc.add(const SelectUndername(
//           undername: ARNSUndername(
//             name: 'undername',
//             domain: 'domain',
//             record: ARNSRecord(transactionId: 'test_tx_id', ttlSeconds: 3600),
//           ),
//         ));
//         bloc.add(ConfirmSelectionAndUpload());
//       },
//       expect: () => [
//         isA<LoadingNames>(),
//         isA<NamesLoaded>(),
//         isA<LoadingUndernames>(),
//         isA<UndernamesLoaded>(),
//         isA<UndernamesLoaded>(),
//         isA<ConfirmingSelection>(),
//         isA<SelectionFailed>(),
//       ],
//       verify: (_) {
//         verify(() => mockArnsRepository.setUndernamesToFile(
//               undername: any(named: 'undername'),
//               fileId: any(named: 'fileId'),
//               driveId: any(named: 'driveId'),
//               processId: any(named: 'processId'),
//             )).called(1);
//       },
//     );
//   });
// }
