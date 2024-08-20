class DriveDAOException implements Exception {
  final String message;
  final Object? error;

  DriveDAOException({required this.message, this.error});

  @override
  String toString() {
    return 'DriveDAOException: $message. Error: ${error.toString()}';
  }
}
