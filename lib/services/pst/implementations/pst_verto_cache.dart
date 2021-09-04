import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

// ArDrive Profit Sharing Community Smart Contract
final cachedContractURL =
    'https://v2.cache.verto.exchange/-8A6RexFkpfWwuyVO98wzSFZh0d6VJuI-buTJvlwOJQ';
// Calls the ArDrive Community Smart Contract to pull the fee
// A return value of .15 means that the retrieved tip setting is 15% of the data upload cost.
Future<double> getArDriveTipPercentage() async {
  try {
    final client = http.Client();

    final settings = (await client
        .get(Uri.parse(cachedContractURL))
        .then((res) => json.decode(res.body)))['state']['settings'];

    final arDriveCommunityFee = settings.firstWhere(
        ((setting) => setting[0].toString().toLowerCase() == 'fee'));

    return arDriveCommunityFee.isNotEmpty ? arDriveCommunityFee[1] / 100 : 0.15;
  } catch (e) {
    return 0.15; // Default fee of 15% if we cannot pull it from the community contract
  }
}

// Gets a random ArDrive token holder based off their weight (amount of tokens they hold)
Future<String> selectTokenHolder() async {
  // Read the ArDrive Smart Contract to get the latest state
  final client = http.Client();

  final res = json
      .decode((await client.get(Uri.parse(cachedContractURL))).body)['state'];
  final balances = res['balances'];
  final vault = res['vault'];

  // Get the total number of tokens
  var totalTokens = 0;
  for (var addr in balances.keys) {
    totalTokens = balances[addr]! + totalTokens;
  }

  // Check for how many tokens the user has staked/vaulted
  for (var addr in vault.keys) {
    if (vault[addr] == null || vault[addr]!.isEmpty) continue;

    final vaultBalance =
        vault[addr]!.map((a) => a['balance']).reduce((a, b) => a! + b!)!;

    totalTokens = vaultBalance + totalTokens;

    if (balances.containsKey(addr)) {
      balances[addr] = (balances[addr]! + vaultBalance);
    } else {
      balances[addr] = vaultBalance;
    }
  }

  // Create a weighted list of token holders
  final weighted = <String, double>{};
  for (var addr in balances.keys) {
    weighted[addr] = (balances[addr]! / totalTokens);
  }
  // Get a random holder based off of the weighted list of holders
  final randomHolder = weightedRandom(weighted);
  return randomHolder ?? '';
}

// Gets a random ardrive wallet, but each wallet has a weight of the tokens it has,
// A wallet with a higher number of tokens has a higher probability of being returned.
String? weightedRandom(Map<String, double> dict) {
  var sum = 0.0;
  final r = Random().nextDouble();

  for (var addr in dict.keys) {
    if (dict[addr] == null) {
      dict[addr] = 0;
    }
    sum += dict[addr]!;
    if (r <= sum && dict[addr]! > 0) {
      return addr;
    }
  }
  return null;
}

Future<double> getWinstonPriceForByteCount(int byteCount) async {
  final client = http.Client();

  final response =
      await client.get(Uri.parse('https://arweave.net/price/$byteCount'));
  final winstonAsString = response.body;
  return double.parse(winstonAsString);
}

Future<double> getPstFeePercentage() => getArDriveTipPercentage();

Future<String> getWeightedPstHolder() => selectTokenHolder();
