enum DriveSignatureType {
  v1('1'),
  v2('2');

  final String value;
  const DriveSignatureType(this.value);

  factory DriveSignatureType.fromString(String value) {
    return DriveSignatureType.values.firstWhere(
      (element) => element.value == value,
      orElse: () => DriveSignatureType.v1,
    );
  }

  @override
  String toString() => value;
}
