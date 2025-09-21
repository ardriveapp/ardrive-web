abstract class IOEntity {
  IOEntity(
      {required this.name, required this.lastModifiedDate, required this.path});

  /// File name on O.S.
  final String name;

  /// Given path on O.S.
  final String path;

  /// Last modified date on O.S.
  final DateTime lastModifiedDate;
}
