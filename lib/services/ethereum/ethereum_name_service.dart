import 'dart:convert';

import 'package:ardrive/utils/logger.dart';
import 'package:http/http.dart' as http;

/// Resolved ENS profile: domain name and optional avatar URL.
class EnsProfile {
  final String domain;
  final String? avatarUrl;

  const EnsProfile({required this.domain, this.avatarUrl});
}

/// Resolves ENS (.eth) domain names and profile data for Ethereum addresses.
///
/// Uses ensdata.net API with in-memory caching to avoid repeated calls.
class EthereumNameService {
  static const _baseUrl = 'https://api.ensdata.net';

  /// In-memory cache: address → resolved profile (or null if none found).
  final Map<String, EnsProfile?> _cache = {};

  /// Returns the ENS profile for the given Ethereum address, or null if none.
  /// Results are cached for the lifetime of the service instance.
  Future<EnsProfile?> getProfile(String ethereumAddress) async {
    final key = ethereumAddress.toLowerCase();
    if (_cache.containsKey(key)) {
      return _cache[key];
    }

    final profile = await _fetchProfile(ethereumAddress);
    _cache[key] = profile;
    return profile;
  }

  /// Clears the cache (e.g., on logout).
  void clearCache() {
    _cache.clear();
  }

  Future<EnsProfile?> _fetchProfile(String ethereumAddress) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/$ethereumAddress'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final ensName = data['ens_primary'] as String?;
      if (ensName == null || ensName.isEmpty) return null;

      final avatarUrl = data['avatar'] as String?;

      return EnsProfile(
        domain: ensName,
        avatarUrl: (avatarUrl != null && avatarUrl.startsWith('http'))
            ? avatarUrl
            : null,
      );
    } catch (e) {
      logger.d('Failed to resolve ENS for $ethereumAddress: $e');
      return null;
    }
  }
}
