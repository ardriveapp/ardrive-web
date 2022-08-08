import 'package:ardrive/pst/pst_contract_data.dart';
import 'package:ardrive/pst/pst_contract_data_builder.dart';
import 'package:ardrive/types/arweave_address.dart';
import 'package:test/test.dart';

import 'constants.dart';

void main() {
  group('CommunityContractDataBuilder', () {
    test('parses a CommunityContractData when fed with healthy data', () {
      final builder = CommunityContractDataBuilder(rawHealthyContractData);
      final output = builder.parse();

      expect(output.name, 'ArDrive');
      expect(output.ticker, 'ARDRIVE');

      final firstBalanceAddress = output.balances.keys.first;
      final firstBalanceValue = output.balances.values.first;
      expect(output.balances, isA<Map<ArweaveAddressType, int>>());
      expect(output.balances.length, 1288);
      expect(
          firstBalanceAddress,
          ArweaveAddress(
            '-0HTOR6F-lebzMQDwSvfaS1VIapN49MKkYVLHxKwWAQ',
          ));
      expect(firstBalanceValue, 10);

      expect(output.settings, isA<CommunityContractSettings>());
      expect(output.settings.quorum, 0.15);
      expect(output.settings.support, 0.5);
      expect(output.settings.voteLength, 2160);
      expect(output.settings.lockMinLength, 5040);
      expect(output.settings.lockMaxLength, 788400);
      expect(output.settings.communityAppUrl, 'https://ardrive.io');
      expect(output.settings.communityDiscussionLinks, [
        'https://discord.gg/ya4hf2H',
        'https://twitter.com/ardriveapp',
      ]);
      expect(
        output.settings.communityDescription,
        'We are a community focused on building the best private, secure, decentralized, pay-as-you-go, censorship-resistant and permanent data storage solution, for everyone.  With ArDrive\'s desktop, mobile and web apps, you can easily sync and share your public and private files from the PermaWeb.',
      );
      expect(
          output.settings.communityLogo,
          ArweaveAddress(
            'tN4vheZxrAIjqCfbs3MDdWTXg8a_57JUNyoqA4uwr1k',
          ));
      expect(output.settings.fee, 15);

      final firstVault = output.vault.entries.toList()[0];
      final firstVaultAddress = firstVault.key;
      final firstVaultItems = firstVault.value;
      final firstVaultItem = firstVaultItems[0];
      expect(output.vault, isA<Map<ArweaveAddressType, List<VaultItem>>>());
      expect(
        firstVaultAddress,
        ArweaveAddress('-OtTqVqAGqTBzhviZptnUTys7rWenNrnQcjGtvDBDdo'),
      );
      expect(
        firstVaultItem.balance,
        500000,
      );
      expect(
        firstVaultItem.start,
        645563,
      );
      expect(
        firstVaultItem.end,
        1433963,
      );

      final firstVote = output.votes[0];
      expect(output.votes, isA<List<CommunityContractVotes>>());
      expect(output.votes.length, 165);
      expect(firstVote.status, VoteStatus.passed);
      expect(firstVote.type, VoteType.mintLocked);
      expect(firstVote.note, 'Advisory tokens, 12 month lockup');
      expect(firstVote.yays, 1182600000000);
      expect(firstVote.nays, 0);
      expect(firstVote.voted.length, 1);
      expect(
        firstVote.voted[0],
        ArweaveAddress('Zznp65qgTIm2QBMjjoEaHKOmQrpTu0tfOcdbkm_qoL4'),
      );
      expect(firstVote.start, 516926);
      expect(firstVote.totalWeight, 1182600000000);
      expect(
        firstVote.recipient,
        ArweaveAddress('rcO1Hi4_chcHVFBpSGOAVHVBBcljdypxlCBCbPfnu-c'),
      );
      expect(firstVote.qty, 50000);
      expect(firstVote.lockLength, 262800);
    });

    test('throws if the name is not ArDrive', () {
      final builder = CommunityContractDataBuilder(rawContractDataWrongName);
      expect(
          () => builder.parse(),
          throwsA(const InvalidCommunityContractData(
            reason: 'Expected the field .name to be "ArDrive"',
          )));
    });

    test('throws if the ticker is not ARDRIVE', () {
      final builder = CommunityContractDataBuilder(rawContractDataWrongTicker);
      expect(
          () => builder.parse(),
          throwsA(const InvalidCommunityContractData(
            reason: 'Expected the field .ticker to be "ARDRIVE"',
          )));
    });

    test('throws if the balances is not a Map', () {
      final builder = CommunityContractDataBuilder(
        rawContractDataWrongBalancesType,
      );
      expect(
          () => builder.parse(),
          throwsA(const InvalidCommunityContractData(
            reason: 'Expected the field .balances to be an object',
          )));
    });

    test('throws if the balances\' key are not a valid Arweave address', () {
      final builder = CommunityContractDataBuilder(
        rawContractDataWrongBalancesKey,
      );
      expect(
          () => builder.parse(),
          throwsA(const InvalidCommunityContractData(
            reason:
                'Expected the key of the field .balances[address] to be a string, got not an address',
          )));
    });

    test('throws if the balances\' value are not a valid integer', () {
      final builder = CommunityContractDataBuilder(
        rawContractDataWrongBalancesValue,
      );
      expect(
          () => builder.parse(),
          throwsA(const InvalidCommunityContractData(
            reason:
                'Expected the field .balances[address] to be an integer, got not an integer',
          )));
    });

    test('throws if the votes value are not a valid integer', () {
      final builder = CommunityContractDataBuilder(
        rawContractDataWrongVotesType,
      );
      expect(
          () => builder.parse(),
          throwsA(const InvalidCommunityContractData(
            reason: 'Expected the field .votes to be an array',
          )));
    });

    test('throws if the votes schema is wrong', () {
      rawContractDataWrongVoteFiledsExpectations
          .forEach((rawData, expectedException) {
        final builder = CommunityContractDataBuilder(
          rawData,
        );
        expect(() => builder.parse(), throwsA(expectedException));
      });
    });
  });
}
