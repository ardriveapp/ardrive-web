import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pst/src/community_oracle.dart';
import 'package:pst/src/constants.dart';
import 'package:pst/src/contract_oracle.dart';
import 'package:pst/src/implementations/token_holder_selector.dart';

import 'constants.dart';
import 'stubs.dart';

final aTransactionId = TransactionID(
  '1111111111111111111111111111111111111111111',
);

class TokenHolderSelectorStub extends Mock implements TokenHolderSelector {}

void main() {
  group('CommunityOracle class', () {
    final myContractReader = ContractReaderStub();
    late ContractOracle myContractOracle;
    late TokenHolderSelectorStub myTokenHolderSelector;
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
      myTokenHolderSelector = TokenHolderSelectorStub();
      myCommunityOracle =
          CommunityOracle(myContractOracle, myTokenHolderSelector);
    });

    group('getCommunityWinstonTip method', () {
      test('returns a percentage of the actual amount', () async {
        final inputAmount = Winston(BigInt.from(999999999999));
        final tipAmount =
            await myCommunityOracle.getCommunityWinstonTip(inputAmount);
        final expectedAmount = Winston(
          // times 100 and divided by 100 because BigInt would only accept integers as input
          inputAmount.value * BigInt.from(0.15 * 100) ~/ BigInt.from(100),
        );
        expect(
          tipAmount,
          expectedAmount,
        );
      });

      test('returns the minimum tip if the percentage is lower', () async {
        final tipAmount =
            await myCommunityOracle.getCommunityWinstonTip(Winston(BigInt.one));
        expect(tipAmount, Winston(BigInt.from(10000000)));
      });
    });

    group('selectTokenHolder method', () {
      const double randomA = .2;
      const double randomB = 1;
      final expectedAddress =
          ArweaveAddress('Zznp65qgTIm2QBMjjoEaHKOmQrpTu0tfOcdbkm_qoL4');

      test('returns a valid address', () async {
        when(() =>
                myTokenHolderSelector.selectTokenHolder(testingRandom: randomA))
            .thenAnswer((_) => Future.value(expectedAddress));

        final addr =
            await myCommunityOracle.selectTokenHolder(testingRandom: randomA);
        expect(addr, expectedAddress);
        verify(() =>
                myTokenHolderSelector.selectTokenHolder(testingRandom: randomA))
            .called(1);
      });

      test('throws if the token holder could not be determined', () async {
        when(() =>
                myTokenHolderSelector.selectTokenHolder(testingRandom: randomB))
            .thenThrow(CouldNotDetermineTokenHolder());

        expect(
          () async =>
              await myCommunityOracle.selectTokenHolder(testingRandom: randomB),
          throwsA(CouldNotDetermineTokenHolder()),
        );
        verify(() =>
                myTokenHolderSelector.selectTokenHolder(testingRandom: randomB))
            .called(1);
      });
    });
  });
}
