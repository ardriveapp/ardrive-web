abstract class ARFSException implements Exception {
  final String message;

  ARFSException(this.message);

  @override
  String toString() {
    return 'ARFSException: $message';
  }
}

class ARFSMultipleNamesForTheSameEntityException extends ARFSException {
  ARFSMultipleNamesForTheSameEntityException()
      : super(
            'More than one folder with the same name found in the same parent folder');
}
