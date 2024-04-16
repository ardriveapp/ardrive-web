class WebFolder {
  final String name;
  final String parentFolderPath;

  String id;
  late String parentFolderId;

  WebFolder({
    required this.name,
    required this.id,
    required this.parentFolderPath,
  });
}
