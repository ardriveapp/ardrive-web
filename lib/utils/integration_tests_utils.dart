bool isIntegrationTest() {
  return const String.fromEnvironment('integration-test') != '';
}
