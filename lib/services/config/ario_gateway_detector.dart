import 'dart:convert';

import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;

/// Service to detect if the app is being served from an AR.IO gateway
/// and automatically configure the gateway for data requests.
class ArIOGatewayDetector {
  static const Duration _requestTimeout = Duration(seconds: 5);

  /// Detects if the current host is an AR.IO gateway and returns the appropriate
  /// gateway configuration for data requests.
  /// 
  /// Returns null if:
  /// - Not running on web platform
  /// - Host is not an AR.IO gateway
  /// - Detection fails
  /// 
  /// Returns [SelectedGateway] if the host is a valid AR.IO gateway.
  static Future<SelectedGateway?> detectArIOGateway() async {
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
      
      // Extract domain from hostname
      final parts = hostGateway.split('.');
      final domain = parts.length > 1 ? parts.sublist(1).join('.') : parts[0];
      
      logger.d('AR.IO gateway detection: Testing domain $domain');
      
      // Test if the domain is an AR.IO gateway
      final isArIOGateway = await _testArIOGateway(domain);
      
      if (isArIOGateway) {
        final gatewayUrl = 'https://$domain';
        logger.i('AR.IO gateway detected: $gatewayUrl');
        
        return SelectedGateway(
          label: 'AR.IO Gateway ($domain)',
          url: gatewayUrl,
        );
      } else {
        logger.d('AR.IO gateway detection: $domain is not an AR.IO gateway');
        return null;
      }
    } catch (error, stackTrace) {
      logger.e('AR.IO gateway detection failed', error, stackTrace);
      return null;
    }
  }

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
        
        logger.d('AR.IO gateway detection: Response has wallet field: $hasWallet');
        return hasWallet;
      } else {
        logger.d('AR.IO gateway detection: HTTP ${response.statusCode} from $uri');
        return false;
      }
    } catch (error) {
      logger.d('AR.IO gateway detection: Error testing $domain - $error');
      return false;
    }
  }
}
