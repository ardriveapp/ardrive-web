String getExtensionFromPath(String path) {
  return path.split('/').last.split('.').last;
}
