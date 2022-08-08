import 'package:ardrive/pst/pst_contract_data.dart';
import 'package:ardrive/types/arweave_address.dart';
import 'package:equatable/equatable.dart';

class CommunityContractDataBuilder {
  final Map _rawData;

  CommunityContractDataBuilder(Map jsonData) : _rawData = jsonData;

  CommunityContractData parse() {
    _validate();

    final List rawVotes = _rawData['votes'];
    final Map rawSettings = Map.fromEntries(
      (_rawData['settings'] as List).map(
        (element) => MapEntry(element[0], element[1]),
      ),
    );
    final Map rawBalances = _rawData['balances'];
    final Map rawVault = _rawData['vault'];

    final List<CommunityContractVotes> votes = rawVotes.map((vote) {
      final VoteStatus status = VoteStatus.values.firstWhere(
          (element) => element.toString() == 'VoteStatus.' + vote['status']);
      final VoteType type = VoteType.values.firstWhere(
          (element) => element.toString() == 'VoteType.' + vote['type']);
      final String note = vote['note'];
      final int yays = vote['yays'];
      final int nays = vote['nays'];
      final List<ArweaveAddressType> voted = (vote['voted'] as List)
          .map(
            (addr) => ArweaveAddress(addr),
          )
          .toList(growable: false);
      final int start = vote['start'];
      final int totalWeight = vote['totalWeight'];
      final ArweaveAddressType? recipient =
          vote['recipient'] != null ? ArweaveAddress(vote['recipient']) : null;
      final int? qty = vote['qty'];
      final int? lockLength = vote['lockLength'];

      return CommunityContractVotes(
          status: status,
          type: type,
          note: note,
          yays: yays,
          nays: nays,
          voted: voted,
          start: start,
          totalWeight: totalWeight,
          recipient: recipient,
          qty: qty,
          lockLength: lockLength);
    }).toList(growable: false);
    final CommunityContractSettings settings = CommunityContractSettings(
      quorum: rawSettings['quorum'],
      support: rawSettings['support'],
      voteLength: rawSettings['voteLength'],
      lockMinLength: rawSettings['lockMinLength'],
      lockMaxLength: rawSettings['lockMaxLength'],
      communityAppUrl: rawSettings['communityAppUrl'],
      communityDiscussionLinks: rawSettings['communityDiscussionLinks'],
      communityDescription: rawSettings['communityDescription'],
      communityLogo: ArweaveAddress(rawSettings['communityLogo']),
      fee: rawSettings['fee'],
    );
    final Map<ArweaveAddressType, int> balances = Map.fromEntries(
      rawBalances.entries.map(
        (entry) => MapEntry(ArweaveAddress(entry.key), entry.value),
      ),
    );
    final Map<ArweaveAddressType, List<VaultItem>> vault = Map.fromEntries(
      rawVault.entries.map<MapEntry<ArweaveAddressType, List<VaultItem>>>(
        (entry) {
          final key = ArweaveAddress(entry.key);
          final value = (entry.value as List).map((vaultItem) {
            final balance = vaultItem['balance'];
            final start = vaultItem['start'];
            final end = vaultItem['end'];
            return VaultItem(balance: balance, start: start, end: end);
          }).toList(growable: false);
          return MapEntry(key, value);
        },
      ),
    );

    return CommunityContractData(
        votes: votes, settings: settings, balances: balances, vault: vault);
  }

  void _validate() {
    _validateName();
    _validateTicker();
    _validateVotes();
    _validateSettings();
    _validateBalances();
    _validateVaults();
  }

  void _validateName() {
    if (_rawData['name'] != 'ArDrive') {
      throw const InvalidCommunityContractData(
        reason: 'Expected the field .name to be "ArDrive"',
      );
    }
  }

  void _validateTicker() {
    if (_rawData['ticker'] != 'ARDRIVE') {
      throw const InvalidCommunityContractData(
        reason: 'Expected the field .ticker to be "ARDRIVE"',
      );
    }
  }

  void _validateVotes() {
    final votes = _rawData['votes'];
    if (votes is! List) {
      throw const InvalidCommunityContractData(
        reason: 'Expected the field .votes to be an array',
      );
    } else {
      for (final Map vote in votes) {
        _validateSingleVote(vote);
      }
    }
  }

  void _validateSingleVote(Map vote) {
    vote.forEach((key, value) {
      switch (key) {
        case 'status':
        case 'type':
        case 'note':
          if (value is! String) {
            throw InvalidCommunityContractData(
              reason:
                  'Expected the field .votes[number].$key to be a string, got $value',
            );
          }
          break;

        case 'recipient':
        case 'target':
        case 'key':
          if (value is! String && value != null) {
            throw InvalidCommunityContractData(
              reason:
                  'Expected the field .votes[number].$key to be a nullable string, got $value',
            );
          }
          break;

        case 'qty':
        case 'lockLength':
          if (value is! int && value != null) {
            throw InvalidCommunityContractData(
              reason:
                  'Expected the field .votes[number].$key to be a nullable integer, got $value',
            );
          }
          break;

        case 'yays':
        case 'nays':
        case 'start':
        case 'totalWeight':
          if (value is! int) {
            throw InvalidCommunityContractData(
              reason:
                  'Expected the field .votes[number].$key to be an integer, got $value',
            );
          }
          break;

        case 'voted':
          if (value is! List) {
            throw InvalidCommunityContractData(
              reason:
                  'Expected the field .votes[number].$key to be an array, got $value',
            );
          }
          break;

        case 'value':
          // TODO: can it be a boolean? Can it be null?
          if (value is! num && value is! String && value is! List) {
            throw InvalidCommunityContractData(
              reason:
                  'Expected the field .votes[number].$key to be a string, integer, or array, got $value',
            );
          }
          break;

        default:
          // ignore: avoid_print
          print('Ignoring unknown field: .votes[number].$key = $value');
          break;
      }
    });
  }

  void _validateSettings() {
    final settings = _rawData['settings'];
    if (settings is! List) {
      throw const InvalidCommunityContractData(
        reason: 'Expected the field .settings to be an array',
      );
    } else {
      for (final dynamic settingsItem in settings) {
        if (settingsItem is! List || settingsItem.length != 2) {
          throw const InvalidCommunityContractData(
            reason:
                'Expected the field .settings[number] to be an array with two elements',
          );
        }
        final String key = settingsItem[0];
        final dynamic value = settingsItem[1];

        switch (key) {
          case 'communityAppUrl':
          case 'communityDescription':
          case 'communityLogo':
            if (value is! String) {
              throw InvalidCommunityContractData(
                reason:
                    'Expected the field .settings[number][1] ($key) to be a string, got $value',
              );
            }
            break;

          case 'quorum':
          case 'support':
          case 'voteLength':
          case 'lockMaxLength':
          case 'lockMinLength':
          case 'fee':
            if (value is! num) {
              throw InvalidCommunityContractData(
                reason:
                    'Expected the field .settings[number][1] ($key) to be an integer, got $value',
              );
            }
            break;

          case 'communityDiscussionLinks':
            if (value is! List) {
              throw InvalidCommunityContractData(
                reason:
                    'Expected the field .settings[number][1] ($key) to be an array, got $value',
              );
            }
            break;

          default:
            // ignore: avoid_print
            print(
              'Ignoring unknown field: .settings[number][1] ($key: $value)',
            );
            break;
        }
      }
    }
  }

  void _validateBalances() {
    final balances = _rawData['balances'];
    if (balances is! Map) {
      throw const InvalidCommunityContractData(
        reason: 'Expected the field .balances to be an object',
      );
    } else {
      final addresses = balances.keys;
      for (final address in addresses) {
        final balance = balances[address];

        try {
          ArweaveAddress(address);
        } on InvalidAddress {
          throw InvalidCommunityContractData(
            reason:
                'Expected the key of the field .balances[address] to be a string, got $address',
          );
        }
        if (balance is! int) {
          throw InvalidCommunityContractData(
            reason:
                'Expected the field .balances[address] to be an integer, got $balance',
          );
        }
      }
    }
  }

  void _validateVaults() {
    final vault = _rawData['vault'];
    if (vault is! Map) {
      throw const InvalidCommunityContractData(
        reason: 'Expected the field .vault to be an object',
      );
    } else {
      final addresses = vault.keys;
      for (final address in addresses) {
        final vaultsOfAddress = vault[address];
        try {
          ArweaveAddress(address);
        } on InvalidAddress {
          throw InvalidCommunityContractData(
            reason:
                'Expected the key of the field .vault[address] to be a string, got $address',
          );
        }
        if (vaultsOfAddress is! List) {
          throw InvalidCommunityContractData(
            reason:
                'Expected the field .vault[address] to be an array, got $vaultsOfAddress',
          );
        } else {
          for (final vaultItem in vaultsOfAddress) {
            _validateSingleVault(vaultItem);
          }
        }
      }
    }
  }

  void _validateSingleVault(Map vaultItem) {
    vaultItem.forEach((key, value) {
      switch (key) {
        case 'balance':
        case 'start':
        case 'end':
          if (value is! int) {
            throw InvalidCommunityContractData(
              reason:
                  'Expected the field .vault[address][number].$key to be in integer, got $value',
            );
          }
          break;
        default:
          // ignore: avoid_print
          print('Ignoring unknown field .vault[address][number].$key');
      }
    });
  }
}

class InvalidCommunityContractData extends Equatable implements Exception {
  static const String _errorMessage = 'Invalid community contract data';
  final String? _reason;

  const InvalidCommunityContractData({String? reason}) : _reason = reason;

  @override
  String toString() {
    final errorMessage =
        _reason != null ? '$_errorMessage. $_reason' : _errorMessage;
    return errorMessage;
  }

  @override
  List<Object?> get props => [_reason];
}
