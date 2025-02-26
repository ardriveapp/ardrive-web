import 'package:ardrive/main.dart';

/// Generates the HTTP and Arweave addresses for an ArNS name
///
/// This function takes a domain and an optional undername to construct
/// the full ArNS addresses. It returns a tuple containing:
/// 1. The HTTP address (https://<undername>_<domain>.ar-io.dev)
/// 2. The Arweave address (ar://<undername>_<domain>)
///
/// If no undername is provided, it constructs the addresses using only the domain.
(String, String) getAddressesFromArns(
    {required String domain, String? undername}) {
  String address = 'https://';
  String arAddress = 'ar://';

  final gateway = configService.config.getGatewayDomain();

  if (undername != null && undername != '@') {
    address = '$address${undername}_';
    arAddress = '$arAddress${undername}_';
  }

  address = address + domain;
  arAddress = arAddress + domain;

  address = '$address.$gateway';
  arAddress = '$arAddress.$gateway';

  return (address, arAddress);
}
