import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pst/src/ardrive_contract_oracle.dart';
import 'package:pst/src/constants.dart';
import 'package:pst/src/contract_oracle.dart';
import 'package:pst/src/pst_contract_data.dart';

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

      // returns the healthy data when the correct TxID is passed
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

        // returns the healthy data when the correct TxID is passed
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

      setUp(() {
        // Puts a delay to test the retries in the broken contract
        // in other case it will returns before the broken one retry more than one time
        when(() => myContractReader.readContract(pstTransactionId)).thenAnswer(
            (_) => Future.delayed(const Duration(seconds: 4))
                .then((value) => rawHealthyContractData));
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
