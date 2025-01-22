import 'package:ardrive/models/database/database.dart';
import 'package:equatable/equatable.dart';

class SearchResult<T> extends Equatable {
  final T result;
  final FolderEntry? parentFolder;
  final Drive drive;
  final bool? hasArNSName;

  /// A unique identifier for this search result, used for duplicate detection
  final String uniqueId;

  /// Indicates whether this result is a duplicate of another result
  final bool isDuplicate;

  /// Reference to the original result if this is a duplicate
  final SearchResult<T>? originalResult;

  SearchResult({
    required this.result,
    this.parentFolder,
    required this.drive,
    this.hasArNSName,
    String? uniqueId,
    this.isDuplicate = false,
    this.originalResult,
  }) : uniqueId = uniqueId ?? _generateUniqueId(result, drive);

  /// Generates a unique identifier based on the result and drive
  static String _generateUniqueId(dynamic result, Drive drive) {
    if (result is FileEntry) {
      return '${drive.id}_${result.id}';
    } else if (result is FolderEntry) {
      return '${drive.id}_${result.id}';
    } else if (result is Drive) {
      return result.id;
    }
    return '${drive.id}_${result.hashCode}';
  }

  /// Creates a duplicate instance of this search result
  SearchResult<T> asDuplicate() {
    return SearchResult<T>(
      result: result,
      parentFolder: parentFolder,
      drive: drive,
      hasArNSName: hasArNSName,
      uniqueId: uniqueId,
      isDuplicate: true,
      originalResult: this,
    );
  }

  @override
  List<Object?> get props => [uniqueId];

  @override
  bool get stringify => true;
}

enum SearchQueryType {
  all,
  files,
  folders,
  drives,
}
