import 'dart:convert';

import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;

/// Service to detect if the app is being served from an AR.IO gateway
/// and automatically configure the gateway for data requests.
class ArIOGatewayDetector {
  static const Duration _requestTimeout = Duration(seconds: 3);

  /// Detects if the current host is an AR.IO gateway and returns the appropriate
  /// gateway configuration for data requests.
  ///
  /// Returns null if:
  /// - Not running on web platform
  /// - Host is not an AR.IO gateway
  /// - Detection fails
  ///
  /// Returns [SelectedGateway] if the host is a valid AR.IO gateway.
  ///
  /// [alsoTryHost] tries the host itself after the domain above it. A publication
  /// page is served from a gateway's sandbox subdomain, whose parent is the
  /// gateway, but a gateway that serves a manifest without redirecting serves
  /// it from its own host, whose parent (`com`, say) is no gateway at all.
  static Future<SelectedGateway?> detectArIOGateway({
    bool alsoTryHost = false,
  }) async {
    // Only run on web platform
    if (!kIsWeb) {
      logger.d('AR.IO gateway detection: Not running on web platform');
      return null;
    }

    try {
      final hostGateway = html.window.location.hostname;
      if (hostGateway == null || hostGateway.isEmpty) {
        logger.d('AR.IO gateway detection: No hostname available');
        return null;
      }

      logger.d('AR.IO gateway detection: Checking host $hostGateway');

      for (final candidate
          in candidateGateways(hostGateway, alsoTryHost: alsoTryHost)) {
        logger.d('AR.IO gateway detection: Testing domain $candidate');

        // Test if the domain is an AR.IO gateway
        if (await _testArIOGateway(candidate)) {
          final gatewayUrl = 'https://$candidate';
          logger.i('AR.IO gateway detected: $gatewayUrl');

          return SelectedGateway(
            label: 'AR.IO Gateway ($candidate)',
            url: gatewayUrl,
          );
        }
        logger.d('AR.IO gateway detection: $candidate is not an AR.IO gateway');
      }
      return null;
    } catch (error, stackTrace) {
      logger.e('AR.IO gateway detection failed', error, stackTrace);
      return null;
    }
  }

  /// The domains worth asking whether they are an AR.IO gateway, for a page
  /// served from [host]: the domain above it, and with [alsoTryHost] the
  /// host itself.
  ///
  /// Never a parent domain with no dot, which is a top-level domain (`com`
  /// above `turbo-gateway.com`); and never [notGateways], ArDrive's
  /// own domain, which serves app.ardrive.io and staging.ardrive.io and is no
  /// gateway: asking it cost every first visit there a request that 404s
  /// before the app could start.
  @visibleForTesting
  static List<String> candidateGateways(
    String host, {
    bool alsoTryHost = false,
  }) {
    final parts = host.split('.');
    final domain = parts.length > 1 ? parts.sublist(1).join('.') : parts[0];
    return {
      if (domain.contains('.') && !notGateways.contains(domain)) domain,
      if (alsoTryHost && !notGateways.contains(host)) host,
    }.toList();
  }

  /// Domains known not to be AR.IO gateways. See [candidateGateways].
  @visibleForTesting
  static const notGateways = {'ardrive.io'};

  /// Tests if a domain is an AR.IO gateway by checking the /ar-io/info endpoint.
  static Future<bool> _testArIOGateway(String domain) async {
    try {
      final uri = Uri.parse('https://$domain/ar-io/info');
      logger.d('AR.IO gateway detection: Testing $uri');

      final response = await http.get(uri).timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        // Check if response contains wallet field (AR.IO gateway indicator)
        final hasWallet = data.containsKey('wallet') && data['wallet'] != null;

        logger.d(
            'AR.IO gateway detection: Response has wallet field: $hasWallet');
        return hasWallet;
      } else {
        logger.d(
            'AR.IO gateway detection: HTTP ${response.statusCode} from $uri');
        return false;
      }
    } catch (error) {
      logger.d('AR.IO gateway detection: Error testing $domain - $error');
      return false;
    }
  }
}
