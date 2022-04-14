class WebFolder {
  final String name;
  final String parentFolderPath;

  String id;
  late String parentFolderId;
  late String path;
  WebFolder({
    required this.name,
    required this.id,
    required this.parentFolderPath,
  });
}
