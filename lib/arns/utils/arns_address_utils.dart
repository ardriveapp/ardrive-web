import 'package:ardrive/utils/constants.dart';

/// Generates the HTTP and Arweave addresses for an ArNS name
///
/// This function takes a domain and an optional undername to construct
/// the full ArNS addresses. It returns a tuple containing:
/// 1. The HTTP address (via [resolveArnsNameUrl], e.g. https://<name>.ar.io)
/// 2. The Arweave address (ar://<name>)
///
/// If no undername is provided, or undername is [@] or empty, it constructs
/// the addresses using only the domain.
(String, String) getAddressesFromArns({
  required String domain,
  String? undername,
}) {
  final name = (undername != null &&
          undername != '@' &&
          undername.isNotEmpty)
      ? '${undername}_$domain'
      : domain;

  final address = resolveArnsNameUrl(name);
  final arAddress = 'ar://$name';

  return (address, arAddress);
}
