import 'package:ardrive/types/arweave_address.dart';

typedef CommunityTipPercentage = double;

/// Shape of the ArDrive Community Smart Contract data
class CommunityContractData {
  CommunityContractData({
    required this.votes,
    required this.settings,
    required this.balances,
    required this.vault,
  });

  final name = 'ArDrive';
  final ticker = 'ARDRIVE';
  final List<CommunityContractVotes> votes;
  final CommunityContractSettings settings;
  final Map<ArweaveAddressType, int> balances;
  final Map<ArweaveAddressType, List<VaultItem>> vault;
}

class CommunityContractVotes {
  CommunityContractVotes({
    required this.status,
    required this.type,
    required this.note,
    required this.yays,
    required this.nays,
    required this.voted,
    required this.start,
    required this.totalWeight,
    this.recipient,
    this.qty,
    this.lockLength,
    this.key,
  });

  final VoteStatus status;
  final VoteType type;
  final String note;
  final int yays;
  final int nays;
  final List<ArweaveAddressType> voted;
  final int start;
  final int totalWeight;
  final ArweaveAddressType? recipient;
  final int? qty;
  final int? lockLength;
  final String? key;
}

enum VoteStatus {
  passed,
  failed,
  active,
  quorumFailed,
}

enum VoteType {
  burnVault,
  mintLocked,
  mint,
  set,
  indicative,
}

class CommunityContractSettings {
  CommunityContractSettings({
    required this.quorum,
    required this.support,
    required this.voteLength,
    required this.lockMinLength,
    required this.lockMaxLength,
    required this.communityAppUrl,
    required this.communityDiscussionLinks,
    required this.communityDescription,
    required this.communityLogo,
    required this.fee,
  });

  final double quorum;
  final double support;
  final int voteLength;
  final int lockMinLength;
  final int lockMaxLength;
  final String communityAppUrl;
  final List<String> communityDiscussionLinks;
  final String communityDescription;
  final ArweaveAddressType communityLogo;
  final int fee;
}

class VaultItem {
  const VaultItem({
    required this.balance,
    required this.start,
    required this.end,
  });

  final int balance;
  final int start;
  final int end;
}
