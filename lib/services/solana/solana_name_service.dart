import 'dart:convert';

import 'package:ardrive/utils/logger.dart';
import 'package:http/http.dart' as http;

/// Resolves Solana Name Service (.sol) domains for a given address.
///
/// Uses the Bonfida SNS SDK proxy to look up the favorite domain
/// associated with a Solana public key.
class SolanaNameService {
  static const _baseUrl = 'https://sdk-proxy.sns.id';

  /// Returns the .sol domain for the given address, or null if none found.
  ///
  /// Queries the user's "favorite domain" which is the primary .sol name
  /// they've set on-chain.
  Future<String?> getFavoriteDomain(String solanaAddress) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/favorite-domain/$solanaAddress'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['s'] == 'ok' && data['result'] is Map) {
          final result = data['result'] as Map<String, dynamic>;
          final name = result['reverse'] as String?;
          if (name != null && name.isNotEmpty) {
            return '$name.sol';
          }
        }
      }

      return null;
    } catch (e) {
      logger.d('Failed to resolve .sol domain for $solanaAddress: $e');
      return null;
    }
  }
}
