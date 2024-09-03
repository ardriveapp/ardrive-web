Map<String, String?> extractNameAndDomain(String input) {
  // Find the position of the last underscore
  int lastUnderscoreIndex = input.lastIndexOf('_');

  // If there's no underscore in the string
  if (lastUnderscoreIndex == -1) {
    return {'name': null, 'domain': input};
  }

  // Split the string into undername and domain
  String undername = input.substring(0, lastUnderscoreIndex);
  String domain = input.substring(lastUnderscoreIndex + 1);

  return {'name': undername, 'domain': domain};
}
