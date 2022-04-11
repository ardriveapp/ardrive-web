import 'package:ardrive/blocs/upload/web_file.dart';

class WebFolder {
  final String name;
  final String parentFolderPath;

  String id;
  List<WebFolder> subFolders = [];
  List<WebFile> files = [];

  WebFolder({
    required this.name,
    required this.id,
    required this.parentFolderPath,
  });
}
