import 'package:ardrive/models/database/database.dart';

class SearchResult<T> {
  final T result;
  final FolderEntry? parentFolder;
  final Drive drive;
  final bool? hasArNSName;

  SearchResult({
    required this.result,
    this.parentFolder,
    required this.drive,
    this.hasArNSName,
  });
}

enum SearchQueryType { name }
