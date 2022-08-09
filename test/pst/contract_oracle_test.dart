import 'package:ardrive/pst/ardrive_contract_oracle.dart';
import 'package:ardrive/pst/constants.dart';
import 'package:ardrive/pst/contract_oracle.dart';
import 'package:ardrive/pst/pst_contract_data.dart';
import 'package:ardrive/types/transaction_id.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'constants.dart';
import 'stubs.dart';

final aTransactionId = TransactionID(
  '1111111111111111111111111111111111111111111',
);

void main() {
  group('ContractOracle class', () {
    final myContractReader = ContractReaderStub();
    late ContractOracle myContractOracle;

    setUp(() {
      registerFallbackValue(aTransactionId);

      // throws if called with a different TxID
      when(() => myContractReader.readContract(any())).thenThrow(Exception(
        'ContractOracle is expected to call the ARDRIVE Smart Contract only!',
      ));

      // returns the healthy data when the correct TxTD is passed
      when(() => myContractReader.readContract(pstTransactionId))
          .thenAnswer((_) => Future.value(rawHealthyContractData));

      myContractOracle = ContractOracle(myContractReader);
    });

    group('getCommunityContract method', () {
      test('returns a valid CommunityContractData', () async {
        final contract = await myContractOracle.getCommunityContract();
        verify(() => myContractReader.readContract(pstTransactionId)).called(1);
        expect(contract, isA<CommunityContractData>());
      });
    });

    group('getTipPercentageFromContract method', () {
      test('returns a valid tip percentage', () async {
        final tipPercentage =
            await myContractOracle.getTipPercentageFromContract();
        expect(tipPercentage, 0.15);
      });
    });

    group('ArDriveContractOracle composite class', () {
      final myBrokenContractReader = ContractReaderStub();
      late ContractOracle myBrokenContractOracle;

      setUp(() {
        reset(myContractReader);

        registerFallbackValue(aTransactionId);

        // throws if called with a different TxID
        when(() => myContractReader.readContract(any())).thenThrow(Exception(
          'ContractOracle is expected to call the ARDRIVE Smart Contract only!',
        ));

        // returns the healthy data when the correct TxTD is passed
        when(() => myContractReader.readContract(pstTransactionId))
            .thenAnswer((_) => Future.value(rawHealthyContractData));

        myContractOracle = ContractOracle(myContractReader);

        // the broken contract reader always throw
        when(() => myBrokenContractReader.readContract(pstTransactionId))
            .thenThrow(Exception(
          'Network error or something',
        ));

        myBrokenContractOracle = ContractOracle(myBrokenContractReader);
      });

      test('throws if an empty array is passed', () {
        expect(
          () => ArDriveContractOracle([]),
          throwsA(const EmptyContractOracles()),
        );
      });

      test(
          'returns a valid CommunityContractData after failing reading the broken oracle',
          () async {
        final communityContractOracle = ArDriveContractOracle([
          myBrokenContractOracle, // the broken one first
          myContractOracle,
        ]);

        final contract = await communityContractOracle.getCommunityContract();

        verify(() => myBrokenContractReader.readContract(pstTransactionId))
            .called(3);

        // TODO: is there a way to use the same mock instead of instantiating a brand new one?
        // the reset method would also un-do the mock calls

        verify(() => myContractReader.readContract(pstTransactionId)).called(1);

        expect(contract, isA<CommunityContractData>());
      });

      test('throws if it fails to read the contract', () async {
        final communityContractOracle =
            ArDriveContractOracle([myBrokenContractOracle]);

        expect(
          () => communityContractOracle.getCommunityContract(),
          throwsA(const CouldNotReadContractState(
            reason: 'Max retry attempts reached',
          )),
        );
      });
    });
  });
}
