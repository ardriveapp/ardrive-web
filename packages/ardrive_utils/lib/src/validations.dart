import 'package:ardrive_utils/ardrive_utils.dart';

bool isValidUuidV4(String uuid) {
  final RegExp uuidV4Pattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$');

  return uuidV4Pattern.hasMatch(uuid.toLowerCase());
}

bool isValidUuidFormat(String uuid) {
  final RegExp uuidPattern =
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

  return uuidPattern.hasMatch(uuid.toLowerCase());
}

bool isValidTxId(String txId) {
  final RegExp txIdPattern = RegExp(r'^[0-9a-f]{64}$');
  return txIdPattern.hasMatch(txId.toLowerCase());
}

bool isValidArweaveTxId(TxID txId) {
  // Check if the length of the string is 43
  if (txId.length != 43) {
    return false;
  }

  // Check if the string contains only base64url valid characters
  final base64UrlRegex = RegExp(r'^[A-Za-z0-9_-]+$');
  return base64UrlRegex.hasMatch(txId);
}
