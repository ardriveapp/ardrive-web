import 'package:ardrive_http/ardrive_http.dart';

class GatewayValidator {
  static const List<String> _validSchemes = ['http', 'https'];
  
  /// Validates if a URL string has the correct format for a gateway
  static bool isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && 
             _validSchemes.contains(uri.scheme.toLowerCase()) &&
             uri.hasAuthority &&
             uri.host.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
  
  /// Cleans and normalizes a gateway URL
  static String cleanUrl(String url) {
    String cleaned = url.trim();
    
    // Remove trailing slashes
    while (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    
    // Add https:// if no scheme provided
    if (!cleaned.startsWith('http://') && !cleaned.startsWith('https://')) {
      cleaned = 'https://$cleaned';
    }
    
    return cleaned;
  }
  
  /// Validates a gateway by testing connectivity and checking if it's an Arweave gateway
  static Future<GatewayValidationResult> validateGateway(String url) async {
    final cleanedUrl = cleanUrl(url);
    
    if (!isValidUrl(cleanedUrl)) {
      return const GatewayValidationResult(
        isValid: false,
        isActive: false,
        isArweaveGateway: false,
        message: 'Invalid URL format. Please use a valid HTTP/HTTPS URL.',
      );
    }
    
    try {
      final http = ArDriveHTTP();
      
      // Try /info endpoint first (Arweave gateway specific)
      try {
        final infoResponse = await http.getAsBytes('$cleanedUrl/info');
        if (infoResponse.statusCode == 200) {
          // Check if response contains Arweave-specific fields
          final responseData = String.fromCharCodes(infoResponse.data);
          final isArweaveGateway = responseData.contains('network') || 
                                 responseData.contains('version') ||
                                 responseData.contains('release');
          
          return GatewayValidationResult(
            isValid: true,
            isActive: true,
            isArweaveGateway: isArweaveGateway,
            message: isArweaveGateway 
              ? 'Gateway is active and appears to be an Arweave gateway.'
              : 'Gateway is active but may not be an Arweave gateway.',
          );
        }
      } catch (e) {
        // Continue to basic check if /info fails
      }
      
      // Basic connectivity check
      final response = await http.getAsBytes(cleanedUrl);
      final isActive = response.statusCode == 200;
      
      return GatewayValidationResult(
        isValid: true,
        isActive: isActive,
        isArweaveGateway: false,
        message: isActive 
          ? 'Gateway is responding but may not be an Arweave gateway.'
          : 'Gateway is not responding. Please check the URL.',
      );
    } catch (e) {
      return const GatewayValidationResult(
        isValid: true,
        isActive: false,
        isArweaveGateway: false,
        message: 'Unable to connect to gateway. Please check the URL and your internet connection.',
      );
    }
  }
  
  /// Extracts a user-friendly label from a gateway URL
  static String generateLabel(String url) {
    try {
      final uri = Uri.parse(cleanUrl(url));
      return 'Custom Gateway (${uri.host})';
    } catch (e) {
      return 'Custom Gateway';
    }
  }
}

class GatewayValidationResult {
  final bool isValid;
  final bool isActive;
  final bool isArweaveGateway;
  final String message;
  
  const GatewayValidationResult({
    required this.isValid,
    required this.isActive,
    required this.isArweaveGateway,
    required this.message,
  });
  
  /// Returns true if the gateway can be used (valid and active)
  bool get canBeUsed => isValid && isActive;
  
  /// Returns true if there should be a warning shown to the user
  bool get shouldShowWarning => isValid && (!isActive || !isArweaveGateway);
  
  /// Returns the appropriate warning level
  GatewayWarningLevel get warningLevel {
    if (!isValid) return GatewayWarningLevel.error;
    if (!isActive) return GatewayWarningLevel.error;
    if (!isArweaveGateway) return GatewayWarningLevel.warning;
    return GatewayWarningLevel.none;
  }
}

enum GatewayWarningLevel {
  none,
  warning,
  error,
}
