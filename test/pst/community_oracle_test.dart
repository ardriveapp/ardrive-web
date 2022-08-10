import 'package:ardrive/pst/community_oracle.dart';
import 'package:ardrive/pst/constants.dart';
import 'package:ardrive/pst/contract_oracle.dart';
import 'package:ardrive/types/arweave_address.dart';
import 'package:ardrive/types/transaction_id.dart';
import 'package:ardrive/types/winston.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'constants.dart';
import 'stubs.dart';

final aTransactionId = TransactionID(
  '1111111111111111111111111111111111111111111',
);

void main() {
  group('CommunityOracle class', () {
    final myContractReader = ContractReaderStub();
    late ContractOracle myContractOracle;
    late CommunityOracle myCommunityOracle;

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
      myCommunityOracle = CommunityOracle(myContractOracle);
    });

    group('getCommunityWinstonTip method', () {
      test('returns a percentage of the actual amount', () async {
        final tipAmount = await myCommunityOracle
            .getCommunityWinstonTip(Winston(BigInt.from(999999999999)));
        expect(tipAmount, Winston(BigInt.from(149999999999)));
      });

      test('returns the minimum tip if the percentage is lower', () async {
        final tipAmount =
            await myCommunityOracle.getCommunityWinstonTip(Winston(BigInt.one));
        expect(tipAmount, Winston(BigInt.from(10000000)));
      });
    });

    group('selectTokenHolder method', () {
      test('returns a valid address', () async {
        final addr = await myCommunityOracle.selectTokenHolder();
        expect(addr, ArweaveAddress('the expected value'));
      });
    }, skip: 'this method uses a random number - FIXME: make me testable');
  });
}
