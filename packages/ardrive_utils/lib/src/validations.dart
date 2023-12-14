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
