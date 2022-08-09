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
  });
}
