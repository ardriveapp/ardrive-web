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

      expect(output.balances, isA<Map<ArweaveAddressType, int>>());
      expect(output.balances.length, 1288);

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
      expect(output.vault, isA<Map<ArweaveAddressType, List<VaultItem>>>());
      expect(
        firstVaultAddress,
        ArweaveAddress('-OtTqVqAGqTBzhviZptnUTys7rWenNrnQcjGtvDBDdo'),
      );
      expect(
        firstVaultItems,
        const [VaultItem(balance: 500000, start: 645563, end: 1433963)],
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
  });
}
