/// Validates if a string is a valid Arweave transaction ID.
bool isArweaveTransactionID(String value) {
  // Arweave transaction IDs are 43 characters long and contain only base64url characters
  final base64urlRegex = RegExp(r'^[a-zA-Z0-9_-]{43}$');
  return base64urlRegex.hasMatch(value);
}
