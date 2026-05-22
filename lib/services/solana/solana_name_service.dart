import 'dart:convert';

import 'package:ardrive/utils/logger.dart';
import 'package:http/http.dart' as http;

/// Resolved .sol profile: domain name and optional profile picture URL.
class SolanaProfile {
  final String domain;
  final String? pictureUrl;

  const SolanaProfile({required this.domain, this.pictureUrl});
}

/// Resolves Solana Name Service (.sol) domains and profile data.
///
/// Uses the Bonfida SNS SDK proxy (sdk-proxy.sns.id) with in-memory caching
/// to avoid repeated API calls within a session.
class SolanaNameService {
  static const _baseUrl = 'https://sdk-proxy.sns.id';

  /// In-memory cache: address → resolved profile (or null if none found).
  /// Persists for the lifetime of the service instance (i.e., the session).
  final Map<String, SolanaProfile?> _cache = {};

  /// Returns the .sol profile for the given address, or null if none found.
  /// Results are cached for the lifetime of the service instance.
  Future<SolanaProfile?> getProfile(String solanaAddress) async {
    if (_cache.containsKey(solanaAddress)) {
      return _cache[solanaAddress];
    }

    final profile = await _fetchProfile(solanaAddress);
    _cache[solanaAddress] = profile;
    return profile;
  }

  /// Clears the cache (e.g., on logout).
  void clearCache() {
    _cache.clear();
  }

  Future<SolanaProfile?> _fetchProfile(String solanaAddress) async {
    try {
      // 1. Get favorite domain
      final domainResponse = await http
          .get(Uri.parse('$_baseUrl/favorite-domain/$solanaAddress'))
          .timeout(const Duration(seconds: 10));

      if (domainResponse.statusCode != 200) return null;

      final domainData =
          jsonDecode(domainResponse.body) as Map<String, dynamic>;
      if (domainData['s'] != 'ok' || domainData['result'] is! Map) return null;

      final result = domainData['result'] as Map<String, dynamic>;
      final name = result['reverse'] as String?;
      if (name == null || name.isEmpty) return null;

      final domain = '$name.sol';

      // 2. Try to get profile picture
      String? pictureUrl;
      try {
        final picResponse = await http
            .get(Uri.parse('$_baseUrl/record/$name/pic'))
            .timeout(const Duration(seconds: 5));

        if (picResponse.statusCode == 200) {
          final picData =
              jsonDecode(picResponse.body) as Map<String, dynamic>;
          if (picData['s'] == 'ok' && picData['result'] is String) {
            final base64Value =
                (picData['result'] as String).replaceAll('\x00', '');
            final decoded = utf8.decode(base64Decode(base64Value));
            if (decoded.startsWith('http')) {
              pictureUrl = decoded;
            }
          }
        }
      } catch (e) {
        // PFP is optional — don't fail the whole resolution
        logger.d('Failed to fetch .sol profile picture: $e');
      }

      return SolanaProfile(domain: domain, pictureUrl: pictureUrl);
    } catch (e) {
      logger.d('Failed to resolve .sol domain for $solanaAddress: $e');
      return null;
    }
  }
}
