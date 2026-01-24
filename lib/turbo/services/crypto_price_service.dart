import 'dart:async';
import 'dart:convert';

import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_http/ardrive_http.dart';

/// Service for fetching real-time cryptocurrency prices from CoinGecko.
///
/// This service provides:
/// - Live USD prices for supported tokens
/// - Automatic caching with configurable TTL
/// - Graceful fallback to cached/default values on error
/// - Batch price fetching for efficiency
class CryptoPriceService {
  final ArDriveHTTP _httpClient;

  /// Cached prices with timestamps
  final Map<CryptoToken, _CachedPrice> _priceCache = {};

  /// Cache duration - prices are valid for this long
  static const _cacheDuration = Duration(minutes: 2);

  /// Default prices to use as fallback (updated periodically)
  static const Map<CryptoToken, double> _defaultPrices = {
    CryptoToken.arioAO: 0.005, // ~$0.005 as of early 2025
    CryptoToken.arioAOViaEth: 0.005,
    CryptoToken.arioBase: 0.005,
    CryptoToken.ethBase: 3000.0,
    CryptoToken.ethL1: 3000.0,
    CryptoToken.sol: 150.0,
    CryptoToken.usdcBase: 1.0,
    CryptoToken.usdcEth: 1.0,
  };

  /// CoinGecko ID mappings for each asset
  static const Map<String, String> _coinGeckoIds = {
    'ario': 'ar-io-network', // AR.IO Network ARIO token
    'eth': 'ethereum',
    'sol': 'solana',
    'usdc': 'usd-coin',
  };

  CryptoPriceService({
    required ArDriveHTTP httpClient,
  }) : _httpClient = httpClient;

  /// Get the current USD price for a token.
  ///
  /// Returns cached price if valid, otherwise fetches from CoinGecko.
  /// Falls back to default price on error.
  Future<double> getUsdPrice(CryptoToken token) async {
    // Check cache first
    final cached = _priceCache[token];
    if (cached != null && !cached.isExpired) {
      return cached.price;
    }

    // Fetch fresh prices
    try {
      await _fetchPrices();
      return _priceCache[token]?.price ?? _getDefaultPrice(token);
    } catch (e) {
      logger.w('Failed to fetch crypto prices, using cached/default: $e');
      return cached?.price ?? _getDefaultPrice(token);
    }
  }

  /// Get USD prices for multiple tokens efficiently.
  ///
  /// Fetches all prices in a single API call.
  Future<Map<CryptoToken, double>> getUsdPrices(
      List<CryptoToken> tokens) async {
    // Check if we need to fetch
    final needsFetch = tokens.any((token) {
      final cached = _priceCache[token];
      return cached == null || cached.isExpired;
    });

    if (needsFetch) {
      try {
        await _fetchPrices();
      } catch (e) {
        logger.w('Failed to fetch crypto prices: $e');
      }
    }

    // Build result map
    final result = <CryptoToken, double>{};
    for (final token in tokens) {
      result[token] = _priceCache[token]?.price ?? _getDefaultPrice(token);
    }
    return result;
  }

  /// Convert token amount to USD value.
  Future<double> tokenToUsd(CryptoToken token, double tokenAmount) async {
    final price = await getUsdPrice(token);
    return tokenAmount * price;
  }

  /// Convert USD amount to token amount.
  Future<double> usdToToken(CryptoToken token, double usdAmount) async {
    final price = await getUsdPrice(token);
    if (price == 0) return 0;
    return usdAmount / price;
  }

  /// Force refresh prices from API.
  Future<void> refreshPrices() async {
    _priceCache.clear();
    await _fetchPrices();
  }

  /// Clear the price cache.
  void clearCache() {
    _priceCache.clear();
  }

  // ============================================
  // Private Methods
  // ============================================

  Future<void> _fetchPrices() async {
    // Build the CoinGecko API URL with all token IDs
    final ids = _coinGeckoIds.values.toSet().join(',');
    final url = 'https://api.coingecko.com/api/v3/simple/price'
        '?ids=$ids&vs_currencies=usd&include_24hr_change=false';

    try {
      final response = await _httpClient.get(url: url);
      final data = jsonDecode(response.data) as Map<String, dynamic>;

      final now = DateTime.now();

      // Parse ETH price
      final ethPrice = _parsePrice(data, 'ethereum');
      if (ethPrice != null) {
        _priceCache[CryptoToken.ethBase] = _CachedPrice(ethPrice, now);
        _priceCache[CryptoToken.ethL1] = _CachedPrice(ethPrice, now);
      }

      // Parse SOL price
      final solPrice = _parsePrice(data, 'solana');
      if (solPrice != null) {
        _priceCache[CryptoToken.sol] = _CachedPrice(solPrice, now);
      }

      // Parse USDC price (should be ~$1)
      final usdcPrice = _parsePrice(data, 'usd-coin') ?? 1.0;
      _priceCache[CryptoToken.usdcBase] = _CachedPrice(usdcPrice, now);
      _priceCache[CryptoToken.usdcEth] = _CachedPrice(usdcPrice, now);

      // Parse ARIO price from CoinGecko (ar-io-network)
      final arioPrice = _parsePrice(data, 'ar-io-network');
      if (arioPrice != null) {
        _priceCache[CryptoToken.arioAO] = _CachedPrice(arioPrice, now);
        _priceCache[CryptoToken.arioAOViaEth] = _CachedPrice(arioPrice, now);
        _priceCache[CryptoToken.arioBase] = _CachedPrice(arioPrice, now);
        logger.d('Fetched ARIO price from CoinGecko: \$$arioPrice');
      } else {
        logger.w('ARIO price not found in CoinGecko response, using default');
      }

      logger.d('Updated crypto prices: ETH=\$${ethPrice ?? "N/A"}, '
          'SOL=\$${solPrice ?? "N/A"}, USDC=\$$usdcPrice, '
          'ARIO=\$${arioPrice ?? "N/A"}');
    } catch (e) {
      logger.e('Error fetching prices from CoinGecko: $e');
      rethrow;
    }
  }

  double? _parsePrice(Map<String, dynamic> data, String coinId) {
    final coinData = data[coinId] as Map<String, dynamic>?;
    if (coinData == null) return null;

    final price = coinData['usd'];
    if (price is num) {
      return price.toDouble();
    }
    return null;
  }

  double _getDefaultPrice(CryptoToken token) {
    return _defaultPrices[token] ?? 1.0;
  }
}

/// Internal class to store cached prices with timestamps.
class _CachedPrice {
  final double price;
  final DateTime fetchedAt;

  _CachedPrice(this.price, this.fetchedAt);

  bool get isExpired =>
      DateTime.now().difference(fetchedAt) > CryptoPriceService._cacheDuration;
}

/// Extension to get price-related info for CryptoToken
extension CryptoPriceExtension on CryptoToken {
  /// Get the CoinGecko ID for this token's underlying asset
  String get coinGeckoId {
    switch (this) {
      case CryptoToken.arioAO:
      case CryptoToken.arioAOViaEth:
      case CryptoToken.arioBase:
        return 'ar-io-network'; // AR.IO Network ARIO token
      case CryptoToken.ethBase:
      case CryptoToken.ethL1:
        return 'ethereum';
      case CryptoToken.sol:
        return 'solana';
      case CryptoToken.usdcBase:
      case CryptoToken.usdcEth:
        return 'usd-coin';
    }
  }
}
